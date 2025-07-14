# DB実践編：PostgreSQL

## 概要

このドキュメントは、PostgreSQLの本格的な運用・管理スキルを体系的に身につけるためのハンズオンガイドです。**「なぜMVCCが重要なのか？」「どのようにJSONBを効率的に検索するか？」**といった実際の運用で直面する課題を、理論的背景とともに実践的に解決する能力を養います。

> **前提知識**: [MySQL版ハンズオン](./mysql.md)で学習した基本的なデータベース概念、Terraform、k6の使い方は理解済みとします。

**なぜPostgreSQL運用スキルが重要なのか？**

- **先進的なアーキテクチャ**: MVCCによる高い並行性とパフォーマンス
- **豊富なデータ型**: JSON、配列、範囲型等による柔軟なデータ表現
- **拡張性**: 拡張機能による無限の可能性とカスタマイズ性
- **オープンソースの信頼性**: エンタープライズレベルの安定性と継続的な進化

**学習目標:**

- PostgreSQL 15の内部アーキテクチャの理解と実践的運用・管理スキル
- MVCC、VACUUM、WALの理論的背景と実践的活用
- 多様なインデックス種類とデータ型の効果的な使い分け
- パーティショニングとクエリ最適化による大規模データの効率的処理
- 拡張機能エコシステムの活用と監視・運用の体系的アプローチ
- マイグレーションとバージョンアップの安全な実践

**PostgreSQL特有の学習内容:**

- MVCC（Multi-Version Concurrency Control）アーキテクチャ
- 豊富なインデックス種類（B-tree、GIN、GiST、BRIN等）
- JSON/JSONB、配列型、ENUM型の活用
- パーティショニング戦略
- VACUUM、WAL、チェックポイント
- 拡張機能エコシステム（PostGIS、pg_stat_statements等）
- 全文検索機能

## 🛠 必要な環境・ツール

### 必須ツール

- **Google Cloud Platform アカウント**（無料クレジット利用可）
- **Terraform** >= 1.0
- **Git**
- **k6** (負荷テストツール)
- **Vim** (エディタ)
- **PostgreSQL Client** (pgcli推奨)

### インストール手順

```bash
# Terraform のインストール (macOS)
brew install terraform

# k6 のインストール
brew install k6

# Google Cloud SDK のインストール
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init

# PostgreSQL Client のインストール
brew install postgresql
pip3 install pgcli
```

### Google Cloud プロジェクトの準備

```bash
# プロジェクトの作成
gcloud projects create postgresql-dbre-training-[YOUR-ID]
gcloud config set project postgresql-dbre-training-[YOUR-ID]

# 必要なAPIの有効化
gcloud services enable compute.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable logging.googleapis.com
```

## 🏗 環境構築

### 基本環境準備

> **MySQL版と共通**: Google Cloud Platform アカウント、Terraform、Git、k6、Vimの準備は[MySQL版 第2章](./mysql.md#第2章-terraformを使ったmysql環境構築)を参照

### PostgreSQL特化Terraform設定

**main.tf**（PostgreSQL特化部分のみ）

```hcl
# Cloud SQL PostgreSQL インスタンス
resource "google_sql_database_instance" "postgres_instance" {
  name             = "postgres-training-instance"
  database_version = "POSTGRES_15"
  region          = var.region

  settings {
    tier              = "db-custom-2-4096"
    disk_size         = 20
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 7
      }
    }

    # PostgreSQL特有のパフォーマンス設定
    database_flags {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements,auto_explain,pg_buffercache"
    }

    database_flags {
      name  = "pg_stat_statements.track"
      value = "all"
    }

    database_flags {
      name  = "auto_explain.log_min_duration"
      value = "1000"
    }

    database_flags {
      name  = "log_statement"
      value = "ddl"
    }

    database_flags {
      name  = "checkpoint_completion_target"
      value = "0.9"
    }

    database_flags {
      name  = "random_page_cost"
      value = "1.1"  # SSD向け調整
    }

    database_flags {
      name  = "effective_cache_size"
      value = "3GB"  # 実際のメモリに応じて調整
    }

    database_flags {
      name  = "maintenance_work_mem"
      value = "256MB"
    }

    database_flags {
      name  = "max_parallel_workers_per_gather"
      value = "2"
    }

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.vpc_network.id
      authorized_networks {
        name  = "all"
        value = "0.0.0.0/0"
      }
    }
  }

  deletion_protection = false
}

# PostgreSQL データベース作成
resource "google_sql_database" "postgres_training_db" {
  name     = "training_db"
  instance = google_sql_database_instance.postgres_instance.name
  charset  = "UTF8"
  collation = "en_US.UTF8"
}

# PostgreSQL ユーザー作成
resource "google_sql_user" "postgres_user" {
  name     = "training_user"
  instance = google_sql_database_instance.postgres_instance.name
  password = var.postgres_password
}
```

**startup-script.sh**（PostgreSQL特化部分）

```bash
#!/bin/bash

# 基本システム更新（MySQL版と共通）
apt-get update && apt-get upgrade -y

# PostgreSQL Client インストール
apt-get install -y postgresql-client-15 postgresql-contrib

# pgcli（高機能PostgreSQLクライアント）
apt-get install -y python3-pip
pip3 install pgcli

# k6 インストール（MySQL版と同じ手順）
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
apt-get update && apt-get install k6

# PostgreSQL監視ツール
apt-get install -y htop iotop sysstat

# Cloud SQL Proxy（MySQL版と同じ）
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
chmod +x cloud_sql_proxy && mv cloud_sql_proxy /usr/local/bin/

echo "PostgreSQL setup completed" >> /var/log/startup-script.log
```

---

## 📚 第1章: PostgreSQL基礎とアーキテクチャ

### 1.1 なぜPostgreSQLのアーキテクチャが革新的なのか？

PostgreSQLのアーキテクチャを理解する上で、**「なぜMVCCが重要なのか？」**という疑問に答えることが重要です。従来のロックベースとは根本的に異なるアプローチを採用しているからです。

### 1.2 PostgreSQLの特徴とMySQLとの根本的違い

#### MVCC（Multi-Version Concurrency Control）

PostgreSQLの心臓部となるMVCCアーキテクチャは、MySQLのロックベースとは根本的に異なります。

**MVCCの仕組み:**

```sql
-- トランザクション分離レベルの確認
SHOW transaction_isolation;

-- MVCC動作デモ
-- セッション1
BEGIN;
UPDATE rooms SET price_per_night = 15000 WHERE id = 1;
SELECT txid_current();  -- 現在のトランザクションID

-- セッション2（別ターミナル）
SELECT price_per_night FROM rooms WHERE id = 1;  -- 古い値が見える
SELECT txid_current_snapshot();  -- 見えるトランザクションの範囲

-- セッション1でCOMMIT後
COMMIT;

-- セッション2で再確認
SELECT price_per_night FROM rooms WHERE id = 1;  -- 新しい値が見える
```

**重要な概念:**

- **タプルバージョン**: 各行の更新で新しいバージョンが作成
- **xmin/xmax**: 各タプルの作成・削除トランザクションID
- **Dead Tuple**: 誰からも見えなくなった古いバージョン

```sql
-- システムカラムの確認
SELECT xmin, xmax, ctid, * FROM rooms WHERE id = 1;
```

#### VACUUM（ガベージコレクション）

MVCCの副作用として発生するDead Tupleの回収が必要です。

```sql
-- VACUUM関連統計
SELECT
    schemaname,
    tablename,
    n_live_tup,
    n_dead_tup,
    ROUND(n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_ratio,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
ORDER BY dead_ratio DESC NULLS LAST;

-- 手動VACUUM実行
VACUUM (ANALYZE, VERBOSE) rooms;

-- VACUUM FULL（テーブル再構築）
VACUUM FULL rooms;  -- 注意：長時間のロックが発生
```

### 1.2 PostgreSQL特有のデータ型とインデックス

#### 豊富なデータ型

```sql
-- ENUM型の定義
CREATE TYPE room_type_enum AS ENUM ('single', 'double', 'suite', 'penthouse');
CREATE TYPE guest_status_enum AS ENUM ('active', 'inactive', 'blocked');

-- 配列型
CREATE TABLE guests (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    preferences TEXT[],  -- 文字列配列
    ratings INTEGER[]    -- 数値配列
);

-- JSONB型（バイナリJSON）
CREATE TABLE room_metadata (
    room_id INTEGER,
    details JSONB
);

-- 範囲型
CREATE TABLE price_ranges (
    id SERIAL PRIMARY KEY,
    room_type VARCHAR(50),
    price_range int4range  -- 整数範囲型
);
```

#### PostgreSQLのインデックス種類

| インデックス種類 | 用途                 | 適用例                               |
| ---------------- | -------------------- | ------------------------------------ |
| **B-tree**       | 一般的な検索・ソート | `=`, `<`, `>`, `BETWEEN`, `ORDER BY` |
| **Hash**         | 等価検索のみ         | `=` のみ（メモリ内のみ）             |
| **GIN**          | 複合データ型         | JSONB, 配列, 全文検索                |
| **GiST**         | 幾何データ・近似検索 | PostGIS, 範囲型, 近似検索            |
| **SP-GiST**      | 空間分割             | IP範囲, テキストパターン             |
| **BRIN**         | 大テーブル・物理順序 | タイムスタンプ順のログテーブル       |

```sql
-- 各種インデックスの実践例

-- 1. B-tree（標準）
CREATE INDEX idx_guest_email ON guests (email);

-- 2. 部分インデックス（PostgreSQL特有）
CREATE INDEX idx_unpaid_reservations
ON room_reservations (guest_id)
WHERE is_paid = false;

-- 3. 関数インデックス
CREATE INDEX idx_guest_name_lower
ON guests (lower(first_name || ' ' || last_name));

-- 4. JSONB用GINインデックス
CREATE INDEX idx_metadata_gin
ON room_reservations USING gin (metadata);

-- 5. 配列用GINインデックス
CREATE INDEX idx_preferences_gin
ON guests USING gin (preferences);

-- 6. 全文検索用GINインデックス
CREATE INDEX idx_fulltext_search
ON rooms USING gin (to_tsvector('english', name || ' ' || description));

-- 7. BRIN（Block Range Index）- 大テーブル向け
CREATE INDEX idx_created_at_brin
ON room_reservations USING brin (created_at);
```

### 📖 参考資料

- [PostgreSQL 15 Documentation](https://www.postgresql.org/docs/15/)
- [PostgreSQL Index Types](https://www.postgresql.org/docs/15/indexes-types.html)
- [MVCC explained](https://www.postgresql.org/docs/15/mvcc.html)

---

## 🏗 第2章: PostgreSQL特化データベース設計

### 2.1 なぜPostgreSQLの拡張機能が強力なのか？

**「どのようにして単一のデータベースで多様な要求に応えるか？」**という疑問に対する答えが、PostgreSQLの拡張機能エコシステムです。

### 2.2 拡張機能の活用

PostgreSQLの真価は豊富な拡張機能にあります。

```sql
-- 利用可能な拡張機能の確認
SELECT name, default_version, comment
FROM pg_available_extensions
ORDER BY name;

-- 重要な拡張機能の有効化
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";      -- UUID生成
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";  -- クエリ統計
CREATE EXTENSION IF NOT EXISTS "pg_buffercache";      -- バッファ分析
CREATE EXTENSION IF NOT EXISTS "pgstattuple";         -- テーブル統計
CREATE EXTENSION IF NOT EXISTS "pg_trgm";             -- 類似検索
```

### 2.3 PostgreSQL活用テーブル設計

```sql
-- 部屋テーブル（JSONB、ENUM、幾何型活用）
CREATE TABLE rooms (
    id SERIAL PRIMARY KEY,
    uuid UUID DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    room_type room_type_enum NOT NULL,
    price_per_night DECIMAL(10, 2) NOT NULL,
    max_guests INTEGER NOT NULL,

    -- JSONB活用（柔軟なメタデータ）
    amenities JSONB,

    -- 幾何データ型（PostGIS無しでも基本的な位置情報）
    location POINT,

    -- 範囲型（価格帯）
    price_range_weekday int4range,
    price_range_weekend int4range,

    -- 配列型（タグ）
    tags TEXT[],

    -- タイムゾーン付きタイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ゲストテーブル（配列、JSONB活用）
CREATE TABLE guests (
    id SERIAL PRIMARY KEY,
    uuid UUID DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    registration_date DATE NOT NULL,
    guest_type guest_status_enum DEFAULT 'active',

    -- 配列型（好み）
    preferences TEXT[],

    -- JSONB（プロファイル情報）
    profile JSONB,

    -- 全文検索用（tsvector）
    search_vector tsvector,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 予約テーブル（パーティション対応）
CREATE TABLE room_reservations (
    id BIGINT GENERATED BY DEFAULT AS IDENTITY,
    uuid UUID DEFAULT uuid_generate_v4(),
    room_id INTEGER NOT NULL REFERENCES rooms(id),
    guest_id INTEGER NOT NULL REFERENCES guests(id),
    guest_number INTEGER NOT NULL DEFAULT 1,
    is_paid BOOLEAN DEFAULT false,

    -- 予約期間（range型）
    stay_period tstzrange NOT NULL,

    reserved_at TIMESTAMP WITH TIME ZONE NOT NULL,
    canceled_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    total_amount DECIMAL(10, 2),
    special_requests TEXT,

    -- 動的メタデータ（JSONB）
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- 除外制約（同じ部屋の期間重複を防ぐ）
    EXCLUDE USING gist (room_id WITH =, stay_period WITH &&)
    WHERE (canceled_at IS NULL)
) PARTITION BY RANGE (created_at);

-- パーティション作成（年別分割）
CREATE TABLE room_reservations_2023 PARTITION OF room_reservations
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE room_reservations_2024 PARTITION OF room_reservations
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE room_reservations_2025 PARTITION OF room_reservations
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- レビューテーブル（全文検索対応）
CREATE TABLE reviews (
    id SERIAL PRIMARY KEY,
    reservation_id BIGINT REFERENCES room_reservations(id),
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    comment_vector tsvector,  -- 全文検索用
    sentiment_score DECIMAL(3, 2),  -- -1.0 to 1.0
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### 2.4 PostgreSQL特化インデックス戦略

```sql
-- 1. 基本的なB-treeインデックス
CREATE INDEX idx_rooms_type ON rooms (room_type);
CREATE INDEX idx_guests_email ON guests (email);

-- 2. JSONB用GINインデックス
CREATE INDEX idx_rooms_amenities
ON rooms USING gin (amenities);

CREATE INDEX idx_guests_profile
ON guests USING gin (profile);

-- JSONBの特定パス用インデックス
CREATE INDEX idx_guest_loyalty
ON guests USING btree ((profile->>'loyalty_level'));

-- 3. 配列用GINインデックス
CREATE INDEX idx_rooms_tags
ON rooms USING gin (tags);

CREATE INDEX idx_guests_preferences
ON guests USING gin (preferences);

-- 4. 全文検索用GINインデックス
CREATE INDEX idx_guests_search
ON guests USING gin (search_vector);

CREATE INDEX idx_reviews_search
ON reviews USING gin (comment_vector);

-- 5. 範囲型用GiSTインデックス
CREATE INDEX idx_reservations_period
ON room_reservations USING gist (stay_period);

-- 6. 複合インデックス
CREATE INDEX idx_reservations_room_created
ON room_reservations (room_id, created_at);

-- 7. 部分インデックス（PostgreSQL特有）
CREATE INDEX idx_unpaid_reservations
ON room_reservations (guest_id, created_at)
WHERE is_paid = false;

CREATE INDEX idx_active_guests
ON guests (email, registration_date)
WHERE guest_type = 'active';

-- 8. 関数インデックス
CREATE INDEX idx_guest_fullname
ON guests (lower(first_name || ' ' || last_name));

-- 9. BRIN（大テーブル向け）
CREATE INDEX idx_reservations_created_brin
ON room_reservations USING brin (created_at);

-- 10. 除外制約インデックス（既にテーブル定義で作成済み）
-- 同じ部屋の期間重複を自動的に防ぐ
```

### 2.5 トリガーによる自動化

```sql
-- 更新時刻自動更新トリガー
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 各テーブルにトリガー設定
CREATE TRIGGER update_rooms_updated_at
    BEFORE UPDATE ON rooms
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_guests_updated_at
    BEFORE UPDATE ON guests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 全文検索ベクトル自動更新
CREATE OR REPLACE FUNCTION update_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := to_tsvector('english',
        COALESCE(NEW.first_name, '') || ' ' ||
        COALESCE(NEW.last_name, '') || ' ' ||
        COALESCE(NEW.email, '')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_guest_search_vector
    BEFORE INSERT OR UPDATE ON guests
    FOR EACH ROW EXECUTE FUNCTION update_search_vector();

-- レビュー全文検索ベクトル更新
CREATE OR REPLACE FUNCTION update_review_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.comment_vector := to_tsvector('english', COALESCE(NEW.comment, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_review_search_vector
    BEFORE INSERT OR UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_review_vector();
```

---

## 🔍 第3章: PostgreSQL パフォーマンス分析

### 3.1 なぜPostgreSQLの分析ツールが優秀なのか？

**「どのようにして正確な原因を特定するか？」**という疑問に対する答えが、PostgreSQLの統計情報収集機能です。MySQLのPerformance Schemaを超越した詳細な分析が可能です。

### 3.2 pg_stat_statements による詳細分析

PostgreSQLの`pg_stat_statements`は、MySQL の Performance Schema 以上の詳細な分析が可能です。

```sql
-- pg_stat_statements の基本確認
SELECT version FROM pg_stat_statements_info;

-- 最も実行時間の長いクエリ TOP 10
SELECT
    LEFT(query, 100) as query_preview,
    calls,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    ROUND(stddev_exec_time::numeric, 2) as stddev_time_ms,
    rows,
    ROUND(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 2) AS hit_percent
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- I/O集約的なクエリの特定
SELECT
    LEFT(query, 100) as query_preview,
    calls,
    shared_blks_read,
    shared_blks_written,
    shared_blks_dirtied,
    shared_blks_hit,
    local_blks_read,
    local_blks_written,
    temp_blks_read,
    temp_blks_written
FROM pg_stat_statements
ORDER BY (shared_blks_read + shared_blks_written) DESC
LIMIT 10;

-- キャッシュミス率の高いクエリ
SELECT
    LEFT(query, 100) as query_preview,
    calls,
    shared_blks_hit,
    shared_blks_read,
    CASE
        WHEN shared_blks_hit + shared_blks_read = 0 THEN 0
        ELSE ROUND(100.0 * shared_blks_read / (shared_blks_hit + shared_blks_read), 2)
    END as cache_miss_percent
FROM pg_stat_statements
WHERE shared_blks_read > 0
ORDER BY cache_miss_percent DESC
LIMIT 10;

-- 一時ファイル使用量の多いクエリ
SELECT
    LEFT(query, 100) as query_preview,
    calls,
    temp_blks_read,
    temp_blks_written,
    ROUND((temp_blks_written * 8192)::numeric / 1024 / 1024, 2) as temp_mb
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 10;
```

### 3.3 PostgreSQL特有の分析クエリ

```sql
-- 現在のアクティビティ詳細
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    state_change,
    wait_event_type,
    wait_event,
    LEFT(query, 200) as query_preview
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;

-- テーブルサイズとVACUUM統計
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    n_live_tup,
    n_dead_tup,
    ROUND(n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_ratio,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- インデックス使用統計
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- 未使用インデックスの特定
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

### 3.4 バッファキャッシュ分析

```sql
-- バッファキャッシュの使用状況
SELECT
    c.relname,
    count(*) as buffers,
    ROUND(100.0 * count(*) / (SELECT setting FROM pg_settings WHERE name='shared_buffers')::integer, 2) as percent_of_cache
FROM pg_buffercache b
INNER JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE b.relfilenode IS NOT NULL
GROUP BY c.relname
ORDER BY count(*) DESC
LIMIT 20;

-- テーブルごとのキャッシュヒット率
SELECT
    schemaname,
    tablename,
    heap_blks_read,
    heap_blks_hit,
    ROUND(100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0), 2) as cache_hit_percent
FROM pg_stat_user_tables
WHERE heap_blks_read + heap_blks_hit > 0
ORDER BY cache_hit_percent ASC;
```

---

## ⚡ 第4章: EXPLAIN分析とクエリ最適化

### 4.1 なぜPostgreSQLのEXPLAINが強力なのか？

**「どのようにして最適な実行計画を作成するか？」**という疑問に対する答えが、PostgreSQLの高度なクエリオプティマイザーです。MySQLを超える詳細な分析情報を提供します。

### 4.2 PostgreSQL EXPLAIN の詳細分析

PostgreSQLのEXPLAINはMySQLより詳細な情報を提供します。

```sql
-- 基本的なEXPLAIN
EXPLAIN SELECT * FROM room_reservations WHERE guest_id = 1000;

-- 実行統計付き（推奨）
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT * FROM room_reservations WHERE guest_id = 1000;

-- JSON形式（詳細分析用）
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT r.name, rr.stay_period
FROM room_reservations rr
JOIN rooms r ON rr.room_id = r.id
WHERE rr.guest_id = 1000;
```

### 4.3 PostgreSQL特有のクエリ最適化

#### JSONB クエリの最適化

```sql
-- 非効率なJSONBクエリ
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM guests
WHERE profile->>'loyalty_level' = 'gold';

-- GINインデックス作成後
CREATE INDEX idx_profile_loyalty
ON guests USING gin ((profile->>'loyalty_level'));

-- 再度実行計画確認
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM guests
WHERE profile->>'loyalty_level' = 'gold';

-- JSONBのoperator選択の重要性
-- 遅い: ?演算子
EXPLAIN ANALYZE
SELECT * FROM rooms WHERE amenities ? 'wifi';

-- 速い: @>演算子
EXPLAIN ANALYZE
SELECT * FROM rooms WHERE amenities @> '{"wifi": true}';
```

#### 配列型クエリの最適化

```sql
-- 配列検索の最適化
-- 遅い: ANY演算子
EXPLAIN ANALYZE
SELECT * FROM guests WHERE 'wifi' = ANY(preferences);

-- 速い: GINインデックス活用
CREATE INDEX idx_preferences_gin ON guests USING gin (preferences);

-- 配列演算子活用
EXPLAIN ANALYZE
SELECT * FROM guests WHERE preferences @> ARRAY['wifi'];

-- 配列の重複検索
EXPLAIN ANALYZE
SELECT * FROM guests WHERE preferences && ARRAY['wifi', 'breakfast'];
```

#### 全文検索の最適化

```sql
-- 基本的な全文検索
EXPLAIN ANALYZE
SELECT * FROM reviews
WHERE to_tsvector('english', comment) @@ to_tsquery('english', 'excellent');

-- tsvectorカラム＋GINインデックス活用
EXPLAIN ANALYZE
SELECT * FROM reviews
WHERE comment_vector @@ to_tsquery('english', 'excellent');

-- 複雑な検索クエリ
EXPLAIN ANALYZE
SELECT *, ts_rank(comment_vector, query) as rank
FROM reviews, to_tsquery('english', 'excellent & service') query
WHERE comment_vector @@ query
ORDER BY rank DESC;
```

#### 範囲型クエリの最適化

```sql
-- 期間重複検索
EXPLAIN ANALYZE
SELECT * FROM room_reservations
WHERE stay_period && tstzrange('2024-12-20', '2024-12-25');

-- GiSTインデックス確認
CREATE INDEX idx_stay_period_gist
ON room_reservations USING gist (stay_period);

-- 範囲型演算子の活用
-- 重複: &&
-- 包含: @>
-- 含まれる: <@
EXPLAIN ANALYZE
SELECT * FROM room_reservations
WHERE stay_period @> '2024-12-22'::timestamptz;
```

### 4.4 パーティション活用最適化

```sql
-- パーティションプルーニング確認
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM room_reservations
WHERE created_at >= '2024-01-01' AND created_at < '2024-02-01';

-- 制約除外の確認
SET constraint_exclusion = partition;

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM room_reservations
WHERE created_at >= '2024-06-01';
```

---

## 📊 第5章: PostgreSQL負荷テスト

### 5.1 なぜPostgreSQLの負荷テストが重要なのか？

**「どのようにして実際の負荷に耐えられるか？」**という疑問に対する答えが、PostgreSQL特有の機能を活用した負荷テストです。JSONB、配列、範囲型などの高度な機能を含めた総合的な検証が必要です。

> **基本的なk6設定**: MySQL版と同様のため、PostgreSQL特有の部分のみ記載

### 5.2 PostgreSQL特化負荷テストスクリプト

```javascript
// postgresql-load-test.js
import { check } from "k6";
import sql from "k6/x/sql";

const db = sql.open(
  "postgres",
  "postgres://training_user:password@localhost:5432/training_db?sslmode=disable",
);

export let options = {
  stages: [
    { duration: "2m", target: 10 },
    { duration: "5m", target: 10 },
    { duration: "2m", target: 20 },
    { duration: "5m", target: 20 },
    { duration: "2m", target: 0 },
  ],
  thresholds: {
    sql_query_duration: ["p(95)<1000"],
    checks: ["rate>0.9"],
  },
};

export default function () {
  let guestId = Math.floor(Math.random() * 100000) + 1;
  let roomId = Math.floor(Math.random() * 1000) + 1;

  // テストケース1: JSONB検索
  let result1 = sql.query(
    db,
    `SELECT COUNT(*) FROM guests 
         WHERE profile->>'loyalty_level' = $1`,
    "gold",
  );

  check(result1, {
    "jsonb search returns result": (r) => r.length > 0,
  });

  // テストケース2: 配列検索
  let result2 = sql.query(
    db,
    `SELECT COUNT(*) FROM guests 
         WHERE preferences @> ARRAY[$1]`,
    "wifi",
  );

  check(result2, {
    "array search returns result": (r) => r.length > 0,
  });

  // テストケース3: 範囲型検索
  let result3 = sql.query(
    db,
    `SELECT COUNT(*) FROM room_reservations 
         WHERE stay_period && tstzrange($1, $2)`,
    "2024-12-20T00:00:00Z",
    "2024-12-25T00:00:00Z",
  );

  check(result3, {
    "range search returns result": (r) => r.length >= 0,
  });

  // テストケース4: 全文検索
  let result4 = sql.query(
    db,
    `SELECT COUNT(*) FROM reviews 
         WHERE comment_vector @@ to_tsquery('english', $1)`,
    "excellent",
  );

  check(result4, {
    "fulltext search returns result": (r) => r.length >= 0,
  });
}

export function teardown() {
  db.close();
}
```

### 5.3 JSONB vs JSON パフォーマンス比較

```javascript
// jsonb-vs-json-test.js
export function setup() {
  // JSONBテーブル作成
  sql.query(
    db,
    `
        CREATE TABLE IF NOT EXISTS test_jsonb (
            id SERIAL PRIMARY KEY,
            data JSONB
        );
        
        CREATE TABLE IF NOT EXISTS test_json (
            id SERIAL PRIMARY KEY,
            data JSON
        );
        
        -- GINインデックス（JSONBのみ）
        CREATE INDEX IF NOT EXISTS idx_test_jsonb_gin 
        ON test_jsonb USING gin (data);
    `,
  );

  // サンプルデータ挿入
  for (let i = 0; i < 10000; i++) {
    let jsonData = JSON.stringify({
      user_id: i,
      preferences: ["wifi", "breakfast"],
      loyalty_level: i % 3 === 0 ? "gold" : "silver",
      last_login: "2024-01-01T00:00:00Z",
    });

    sql.query(db, "INSERT INTO test_jsonb (data) VALUES ($1)", jsonData);
    sql.query(db, "INSERT INTO test_json (data) VALUES ($1)", jsonData);
  }
}

export default function () {
  // JSONB検索（インデックス活用）
  let start = Date.now();
  sql.query(
    db,
    "SELECT COUNT(*) FROM test_jsonb WHERE data->>'loyalty_level' = 'gold'",
  );
  let jsonbTime = Date.now() - start;

  // JSON検索（フルスキャン）
  start = Date.now();
  sql.query(
    db,
    "SELECT COUNT(*) FROM test_json WHERE data->>'loyalty_level' = 'gold'",
  );
  let jsonTime = Date.now() - start;

  console.log(`JSONB: ${jsonbTime}ms, JSON: ${jsonTime}ms`);
}
```

---

## 📈 第6章: PostgreSQL監視とトラブルシューティング

### 6.1 なぜPostgreSQLの監視が複雑なのか？

**「どのようにして先手を打った対策を講じるか？」**という疑問に対する答えが、PostgreSQLの包括的な監視戦略です。MVCC、VACUUM、WALなどの特有の仕組みを理解した監視が必要です。

> **基本的な監視概念**: MySQL版と共通のため、PostgreSQL特有の監視項目に焦点

### 6.2 PostgreSQL特有の監視項目

```sql
-- 1. WAL（Write-Ahead Logging）統計
SELECT
    wal_records,
    wal_fpi,
    wal_bytes,
    wal_buffers_full,
    wal_write,
    wal_sync,
    wal_write_time,
    wal_sync_time
FROM pg_stat_wal;

-- 2. チェックポイント統計
SELECT
    checkpoints_timed,
    checkpoints_req,
    checkpoint_write_time,
    checkpoint_sync_time,
    buffers_checkpoint,
    buffers_clean,
    maxwritten_clean,
    buffers_backend,
    buffers_backend_fsync,
    buffers_alloc
FROM pg_stat_bgwriter;

-- 3. レプリケーション遅延（該当する場合）
SELECT
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication;

-- 4. 拡張機能統計
SELECT
    extname,
    extversion
FROM pg_extension;
```

### 6.3 VACUUM とAUTOVACUUM の監視

```sql
-- VACUUM進行状況監視
SELECT
    pid,
    datname,
    usename,
    state,
    query_start,
    LEFT(query, 100) as current_query
FROM pg_stat_activity
WHERE query LIKE '%VACUUM%' AND state != 'idle';

-- AUTOVACUUM設定確認
SELECT
    name,
    setting,
    unit,
    context
FROM pg_settings
WHERE name LIKE '%autovacuum%'
ORDER BY name;

-- テーブル別VACUUM必要性
SELECT
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    ROUND(n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_ratio,
    last_autovacuum,
    (SELECT setting::integer FROM pg_settings WHERE name = 'autovacuum_vacuum_threshold') +
    (SELECT setting::float FROM pg_settings WHERE name = 'autovacuum_vacuum_scale_factor') * n_live_tup AS vacuum_threshold
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY dead_ratio DESC;
```

### 6.4 緊急時対応プレイブック（PostgreSQL版）

```bash
#!/bin/bash
# postgresql-emergency-playbook.sh

echo "=== PostgreSQL Emergency Response Playbook ==="
echo "Time: $(date)"

PGHOST="127.0.0.1"
PGUSER="training_user"
PGDATABASE="training_db"

# 1. 基本接続確認
echo "1. Connection Test"
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "SELECT version();" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Database connection OK"
else
    echo "✗ Database connection FAILED"
    exit 1
fi

# 2. 現在のアクティビティ
echo "2. Current Activity"
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "
    SELECT
        pid,
        usename,
        state,
        wait_event_type,
        wait_event,
        query_start,
        LEFT(query, 100) as query
    FROM pg_stat_activity
    WHERE state != 'idle'
    ORDER BY query_start;"

# 3. ロック状況
echo "3. Lock Status"
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "
    SELECT
        bl.pid AS blocked_pid,
        ka.query AS blocked_query,
        kl.pid AS blocking_pid,
        a.query AS blocking_query
    FROM pg_catalog.pg_locks bl
    JOIN pg_catalog.pg_stat_activity ka ON ka.pid = bl.pid
    JOIN pg_catalog.pg_locks kl ON kl.transactionid = bl.transactionid AND kl.pid != bl.pid
    JOIN pg_catalog.pg_stat_activity a ON a.pid = kl.pid
    WHERE NOT bl.granted;"

# 4. 最も重いクエリ
echo "4. Heavy Queries"
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "
    SELECT
        LEFT(query, 100) as query_preview,
        calls,
        ROUND(total_exec_time::numeric, 2) as total_time_ms,
        ROUND(mean_exec_time::numeric, 2) as avg_time_ms
    FROM pg_stat_statements
    ORDER BY total_exec_time DESC
    LIMIT 5;"

# 5. テーブルサイズとVACUUM状況
echo "5. Table Sizes and VACUUM Status"
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "
    SELECT
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
        n_dead_tup,
        ROUND(n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_ratio,
        last_autovacuum
    FROM pg_stat_user_tables
    ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
    LIMIT 10;"

echo "=== Emergency Check Completed ==="
```

---

## 🔄 第7章: PostgreSQLマイグレーションとバージョンアップ

### 7.1 なぜPostgreSQLのマイグレーションが重要なのか？

**「どのようにして安全に移行・更新するか？」**という疑問に対する答えが、体系的なマイグレーション戦略です。PostgreSQLの拡張機能と高度な機能を活用した移行手法が必要です。

### 7.2 PostgreSQL マイナーバージョンアップ

```bash
# Terraformでのバージョンアップ（15.4 → 15.5等）
vim main.tf
```

```hcl
resource "google_sql_database_instance" "postgres_instance" {
  database_version = "POSTGRES_15"  # マイナーバージョンは自動更新

  settings {
    maintenance_window {
      hour         = 3
      day          = 7  # 日曜日
      update_track = "stable"
    }
  }
}
```

### 7.3 PostgreSQL メジャーバージョンアップ（15 → 16）

```sql
-- アップグレード前チェック
-- 1. 拡張機能の互換性確認
SELECT
    extname,
    extversion,
    (SELECT default_version FROM pg_available_extensions WHERE name = extname) as available_version
FROM pg_extension;

-- 2. 非互換機能の使用確認
-- 特定の関数やデータ型の使用状況をチェック

-- 3. 統計情報収集
ANALYZE;
```

### 7.4 MySQL → PostgreSQL マイグレーション

#### データ型マッピング

| MySQL            | PostgreSQL                | 備考                      |
| ---------------- | ------------------------- | ------------------------- |
| `AUTO_INCREMENT` | `SERIAL` or `BIGSERIAL`   |                           |
| `TINYINT(1)`     | `BOOLEAN`                 |                           |
| `DATETIME`       | `TIMESTAMP`               | タイムゾーン考慮          |
| `JSON`           | `JSONB`                   | PostgreSQLではJSONBを推奨 |
| `ENUM('a','b')`  | `CREATE TYPE ... AS ENUM` |                           |
| `TEXT`           | `TEXT`                    | 同じ                      |

#### 自動化マイグレーションスクリプト

```python
#!/usr/bin/env python3
# mysql_to_postgresql_migration.py

import mysql.connector
import psycopg2
import psycopg2.extras
import json
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MYSQL_CONFIG = {
    'host': '127.0.0.1',
    'user': 'training_user',
    'password': 'password',
    'database': 'training_db'
}

POSTGRES_CONFIG = {
    'host': '127.0.0.1',
    'user': 'training_user',
    'password': 'password',
    'database': 'training_db'
}

def convert_mysql_to_postgres_ddl():
    """MySQL DDLをPostgreSQL DDLに変換"""

    conversions = {
        # データ型変換
        'AUTO_INCREMENT': 'SERIAL',
        'TINYINT(1)': 'BOOLEAN',
        'DATETIME': 'TIMESTAMP WITH TIME ZONE',
        'JSON': 'JSONB',
        'TEXT': 'TEXT',

        # MySQL特有構文の削除
        'ENGINE=InnoDB': '',
        'DEFAULT CHARSET=utf8mb4': '',
        'COLLATE=utf8mb4_unicode_ci': '',
    }

    # DDL変換ロジック実装
    pass

def migrate_data_with_transformation():
    """データ移行時の変換処理"""

    mysql_conn = mysql.connector.connect(**MYSQL_CONFIG)
    postgres_conn = psycopg2.connect(**POSTGRES_CONFIG)

    try:
        # JSON列の変換（MySQL JSON → PostgreSQL JSONB）
        mysql_cursor = mysql_conn.cursor(dictionary=True)
        postgres_cursor = postgres_conn.cursor()

        # 例: metadata列の変換
        mysql_cursor.execute("SELECT id, metadata FROM room_reservations WHERE metadata IS NOT NULL")

        for row in mysql_cursor.fetchall():
            # MySQL JSONをPython dictに変換後、PostgreSQL JSONBに
            if row['metadata']:
                json_data = json.loads(row['metadata']) if isinstance(row['metadata'], str) else row['metadata']
                postgres_cursor.execute(
                    "UPDATE room_reservations SET metadata = %s WHERE id = %s",
                    (json.dumps(json_data), row['id'])
                )

        postgres_conn.commit()
        logger.info("JSON data migration completed")

    finally:
        mysql_conn.close()
        postgres_conn.close()

if __name__ == "__main__":
    migrate_data_with_transformation()
```

### 7.5 NoSQL → PostgreSQL マイグレーション

```python
# mongodb_to_postgresql.py
from pymongo import MongoClient
import psycopg2
import json

def migrate_mongodb_documents():
    """MongoDB文書をPostgreSQLのJSONBとして移行"""

    mongo_client = MongoClient('mongodb://localhost:27017/')
    mongo_db = mongo_client.hotel_booking

    postgres_conn = psycopg2.connect(**POSTGRES_CONFIG)
    postgres_cursor = postgres_conn.cursor()

    # 文書型データをJSONBとして格納するテーブル
    postgres_cursor.execute("""
        CREATE TABLE IF NOT EXISTS document_store (
            id SERIAL PRIMARY KEY,
            collection_name VARCHAR(100) NOT NULL,
            document_id VARCHAR(100) NOT NULL,
            document_data JSONB NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(collection_name, document_id)
        );

        CREATE INDEX IF NOT EXISTS idx_document_data_gin
        ON document_store USING gin (document_data);
    """)

    # MongoDBコレクションを順次移行
    for collection_name in mongo_db.list_collection_names():
        collection = mongo_db[collection_name]

        for doc in collection.find():
            doc_id = str(doc.pop('_id'))  # ObjectIdを文字列に変換

            postgres_cursor.execute("""
                INSERT INTO document_store (collection_name, document_id, document_data)
                VALUES (%s, %s, %s)
                ON CONFLICT (collection_name, document_id)
                DO UPDATE SET document_data = EXCLUDED.document_data
            """, (collection_name, doc_id, json.dumps(doc, default=str)))

    postgres_conn.commit()
    postgres_conn.close()
    mongo_client.close()
```

---

## 🎯 第8章: PostgreSQL実践課題

### 8.1 なぜ実践課題が学習に重要なのか？

**「どのようにして理論を実践に結び付けるか？」**という疑問に対する答えが、実際のシナリオベースの課題です。PostgreSQLの高度な機能を組み合わせた実践的な問題解決能力を養います。

### 8.2 実践課題1: JSONB検索最適化

**シナリオ**: ゲストプロファイルのJSONB検索が遅い

```sql
-- 問題のクエリ
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM guests
WHERE profile->>'loyalty_level' = 'gold'
  AND (profile->>'points')::integer > 5000;

-- あなたのタスク:
-- 1. 適切なインデックスを設計する
-- 2. クエリを最適化する
-- 3. パフォーマンス改善を測定する

-- 解答例（自分で考えてから確認）:
/*
-- 部分インデックス＋関数インデックス
CREATE INDEX idx_gold_members
ON guests USING btree ((profile->>'loyalty_level'))
WHERE profile->>'loyalty_level' = 'gold';

CREATE INDEX idx_loyalty_points
ON guests USING btree (((profile->>'points')::integer))
WHERE (profile->>'points')::integer > 1000;

-- または複合的なGINインデックス
CREATE INDEX idx_profile_gin ON guests USING gin (profile);
*/
```

### 8.3 実践課題2: パーティション戦略設計

**シナリオ**: 予約テーブルが10億件になりパフォーマンスが劣化

```sql
-- 現在のテーブル構造
\d+ room_reservations

-- あなたのタスク:
-- 1. 最適なパーティション戦略を設計
-- 2. 既存データを新しいパーティション構造に移行
-- 3. パーティションプルーニングの効果を確認

-- 考慮点:
-- - クエリパターン（日付範囲、room_id検索が多い）
-- - データ保持期間（3年）
-- - 過去データのアーカイブ戦略
```

### 8.4 実践課題3: 全文検索システム構築

```sql
-- レビューテーブルに多言語全文検索を実装

-- 要件:
-- 1. 日本語・英語・韓国語対応
-- 2. 類似検索機能
-- 3. ランキング機能
-- 4. リアルタイム検索

-- ヒント: pg_trgm, 複数言語辞書, ts_rank
```

### 8.5 PostgreSQL DBA スキルチェックリスト

#### 基礎レベル ✅

- [ ] PostgreSQLの基本的なCRUD操作
- [ ] EXPLAIN (ANALYZE, BUFFERS)の読み方
- [ ] 基本的なB-treeインデックス設計
- [ ] pg_dumpを使ったバックアップ・リストア

#### 中級レベル ⭐

- [ ] MVCC、VACUUM、WALの理解
- [ ] JSON/JSONB操作とGINインデックス
- [ ] 配列型、ENUM型、範囲型の活用
- [ ] pg_stat_statementsによる分析
- [ ] パーティショニング設計

#### 上級レベル 🚀

- [ ] 拡張機能の設計・開発
- [ ] 複雑なクエリ最適化
- [ ] レプリケーション設定・管理
- [ ] カスタム演算子・関数作成
- [ ] 大規模システムのパフォーマンスチューニング

---

## 📖 継続学習リソース

### PostgreSQL特化リソース

#### 必読書籍

- 「PostgreSQL徹底入門」
- 「PostgreSQL High Performance」
- 「PostgreSQL Administration Cookbook」

#### 公式ドキュメント

- [PostgreSQL 15 Documentation](https://www.postgresql.org/docs/15/)
- [PostgreSQL Performance Tips](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [PostgreSQL Indexes](https://www.postgresql.org/docs/15/indexes.html)

#### コミュニティ・ブログ

- [Planet PostgreSQL](https://planet.postgresql.org/)
- [PostgreSQL Weekly](https://postgresweekly.com/)
- [2ndQuadrant Blog](https://www.2ndquadrant.com/en/blog/)

#### 実践環境

- [PostgreSQL Exercises](https://pgexercises.com/)
- [PostGIS Tutorial](https://postgis.net/workshops/postgis-intro/)
- [PostgreSQL Official Docker](https://hub.docker.com/_/postgres)

### 関連技術スタック

#### 監視・運用ツール

- **pgAdmin**: Web GUI管理ツール
- **pgBadger**: ログ解析ツール
- **pg_stat_kcache**: カーネルキャッシュ統計
- **Patroni**: 高可用性クラスタ管理

#### 拡張機能

- **PostGIS**: 地理空間データ
- **TimescaleDB**: 時系列データ
- **pg_partman**: パーティション管理
- **pg_repack**: オンライン VACUUM FULL

---

## 🎯 総括

本PostgreSQLハンズオンでは、MySQLとは異なる以下の特徴的な技術を習得しました：

### 🔑 核心技術

1. **MVCCアーキテクチャ**: 読み書き競合のない並行制御
2. **豊富なインデックス**: GIN、GiST、BRIN等の特殊用途インデックス
3. **JSONB**: 高性能なバイナリJSON処理
4. **配列・範囲型**: リレーショナルを超えたデータ型
5. **拡張機能**: PostgreSQLの無限の可能性

### 💡 実践スキル

- pg_stat_statementsによる詳細なパフォーマンス分析
- パーティショニングによる大規模データ管理
- 全文検索エンジンとしてのPostgreSQL活用
- NoSQLライクなJSONB操作

### 🚀 次のステップ

PostgreSQLは単なるリレーショナルデータベースを超えた「オブジェクトリレーショナルデータベース」です。地理空間データ（PostGIS）、時系列データ（TimescaleDB）、機械学習（MADlib）など、様々な領域で活用できます。

**継続学習により、真の PostgreSQL エキスパートを目指してください！**

---

> **関連ハンズオン**
>
> - [MySQL版ハンズオン](./mysql.md) - PostgreSQL学習の前提知識
> - Redis版ハンズオン（予定）- キャッシュ・セッション管理
> - MongoDB版ハンズオン（予定）- ドキュメントデータベース
