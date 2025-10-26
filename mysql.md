# DB実践編：MySQL（PostgreSQL差分学習）

## 概要

このドキュメントは、**PostgreSQL を既に学習済みの方向け** に、MySQL 特有の機能と PostgreSQL との違いに焦点を当てた差分学習ガイドです。

> **前提知識**: [PostgreSQL ハンズオン](./postgresql.md) で RDBMS の基礎（MVCC、インデックス、クエリ最適化等）を習得済みであることを前提とします。

**なぜ MySQL を学ぶのか？**

- **実務での採用率が高い**: Web サービスでの採用実績が豊富
- **PostgreSQL との違いを理解**: アーキテクチャの差異を知ることで RDBMS 全般の理解が深まる
- **適材適所の判断**: プロジェクトに応じた DB 選定ができる

**学習目標:**

- PostgreSQL と MySQL のアーキテクチャの違いを理解
- InnoDB ストレージエンジンの特性を理解
- MySQL 特有のレプリケーション方式を習得
- PostgreSQL からの移行ポイントを把握

## 🔄 PostgreSQL vs MySQL - 主要な違い

### アーキテクチャ比較

| 項目 | PostgreSQL | MySQL (InnoDB) | 学習のポイント |
|------|------------|----------------|---------------|
| **並行制御** | MVCC (タプルバージョン管理) | MVCC + Undo Log | PostgreSQL は Dead Tuple、MySQL は Undo Log による実装差 |
| **ストレージ** | 単一アーキテクチャ | プラガブルストレージエンジン | InnoDB, MyISAM 等の選択可能性 |
| **レプリケーション** | ロジカル/物理レプリケーション | バイナリログベース | MySQL は Statement/Row/Mixed 形式 |
| **トランザクション分離** | 4レベル完全対応 | 4レベル対応（実装差あり） | Repeatable Read のデフォルト動作が異なる |
| **インデックス** | B-tree, GIN, GiST, BRIN等 | B+tree（主）, Full-text, Spatial | PostgreSQL の方が多様だが、MySQL も基本は網羅 |
| **JSONB** | ネイティブ JSONB（高速） | JSON 型（PostgreSQL より低速） | PostgreSQL の JSONB が優位 |
| **全文検索** | ネイティブ対応（tsvector） | FULLTEXT INDEX | 実装方式が異なる |
| **拡張機能** | 豊富な拡張（PostGIS等） | プラグイン（限定的） | PostgreSQL の方が拡張性高い |
| **SQL方言** | 標準SQL準拠度高い | 独自拡張多い | 文法の細かい違いあり |

### ロック機構の違い

```sql
-- PostgreSQL: MVCC により読み取りはブロックされない
-- セッション1
BEGIN;
UPDATE rooms SET price = 15000 WHERE id = 1;
-- まだ COMMIT していない

-- セッション2（別セッション）
SELECT * FROM rooms WHERE id = 1;  -- ブロックされない（古いバージョンが見える）

-- MySQL (InnoDB): 同様に MVCC で対応（ただし Undo Log 方式）
-- セッション1
START TRANSACTION;
UPDATE rooms SET price = 15000 WHERE id = 1;

-- セッション2
SELECT * FROM rooms WHERE id = 1;  -- ブロックされない（Undo Log から読み取り）

-- 違いは内部実装:
-- PostgreSQL → Dead Tuple が残り、VACUUM で回収
-- MySQL → Undo Log に保持、Purge スレッドで削除
```

### デフォルト動作の違い

```sql
-- PostgreSQL: トランザクション分離レベルは READ COMMITTED
SHOW transaction_isolation;
-- read committed

-- MySQL: デフォルトは REPEATABLE READ
SELECT @@transaction_isolation;
-- REPEATABLE-READ

-- PostgreSQL: AUTO_INCREMENT に相当
CREATE TABLE users (
    id SERIAL PRIMARY KEY,  -- PostgreSQL
    name VARCHAR(100)
);

-- MySQL: AUTO_INCREMENT
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,  -- MySQL
    name VARCHAR(100)
);

-- PostgreSQL: 文字列連結
SELECT 'Hello' || ' ' || 'World';  -- PostgreSQL

-- MySQL: 文字列連結（複数の方法）
SELECT CONCAT('Hello', ' ', 'World');  -- MySQL 推奨
-- または
SET sql_mode = 'PIPES_AS_CONCAT';
SELECT 'Hello' || ' ' || 'World';  -- PostgreSQL互換モード
```

## 🛠 必要な環境・ツール

> **PostgreSQL版と共通**: 環境構築は [PostgreSQL版](./postgresql.md) を参照してください。MySQL特有の設定のみ以下に記載します。

```bash
# MySQL Client のインストール
brew install mysql-client

# Cloud SQL MySQL 用の設定
gcloud services enable sqladmin.googleapis.com
```

## 📚 第1章: MySQL特有の機能とPostgreSQL差分

> **PostgreSQL で学習済みの内容**: B-tree インデックス、MVCC、トランザクション分離レベルは [PostgreSQL ハンズオン](./postgresql.md) で既習。ここでは MySQL 特有の内容のみ扱います。

### 1.1 InnoDB ストレージエンジンの特性

#### ストレージエンジンの選択可能性（PostgreSQL との大きな違い）

```sql
-- MySQL: ストレージエンジン選択可能
CREATE TABLE users_innodb (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100)
) ENGINE=InnoDB;  -- トランザクション対応

CREATE TABLE temp_data (
    id INT,
    data TEXT
) ENGINE=MyISAM;  -- 高速だがトランザクション非対応

CREATE TABLE memory_cache (
    key_name VARCHAR(50) PRIMARY KEY,
    value TEXT
) ENGINE=MEMORY;  -- インメモリ

-- PostgreSQL: ストレージエンジンの選択概念なし（単一アーキテクチャ）
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100)
);  -- 常に MVCC 対応
```

**InnoDB vs MyISAM 比較**

| 機能 | InnoDB | MyISAM | PostgreSQL |
|------|--------|--------|------------|
| トランザクション | ✅ | ❌ | ✅ |
| MVCC | ✅ | ❌ | ✅ |
| 外部キー | ✅ | ❌ | ✅ |
| 行ロック | ✅ | テーブルロックのみ | ✅（MVCC） |
| 全文検索 | ✅ (5.6+) | ✅ | ✅（tsvector） |
| 用途 | 本番DB | 一時データ、読み取り専用 | すべて |

#### Clustered Index（クラスタインデックス）

**PostgreSQL との最大の違い:**

```sql
-- MySQL InnoDB: PRIMARY KEY = Clustered Index
CREATE TABLE rooms (
    id INT AUTO_INCREMENT PRIMARY KEY,  -- これがデータ格納順序を決定
    room_number VARCHAR(10),
    price DECIMAL(10,2)
);

-- PostgreSQL: ヒープテーブル（挿入順に格納）
CREATE TABLE rooms (
    id SERIAL PRIMARY KEY,  -- インデックスは別構造
    room_number VARCHAR(10),
    price DECIMAL(10,2)
);
```

**Clustered Index の仕組み:**

```
MySQL InnoDB:
PRIMARY KEY = Clustered Index（データ本体を含む）

        [id=50]  ← B+tree ルート
       /        \
  [id=25]       [id=75]  ← 中間ノード
   /    \         /    \
[id=1-24] [id=25-49] [id=50-74] [id=75-100]  ← リーフノード（実データを含む）
 ┌──────────┐
 │id=25     │
 │name='...'│  ← 実際のデータがリーフに格納
 │price=...│
 └──────────┘

PostgreSQL:
PRIMARY KEY = 通常の B-tree Index

        [id=50, pointer]  ← B+tree
       /        \
  [id=25, ptr] [id=75, ptr]
   
   リーフノードはポインタのみ
   実データはヒープ領域に別途格納
```

**セカンダリインデックスの違い:**

```sql
-- MySQL: セカンダリインデックスは PRIMARY KEY を含む
CREATE INDEX idx_room_number ON rooms (room_number);

-- 内部構造:
-- room_number → PRIMARY KEY (id) → データ
-- 2段階アクセスが必要

-- PostgreSQL: セカンダリインデックスは TID (Tuple ID) を含む
CREATE INDEX idx_room_number ON rooms (room_number);

-- 内部構造:
-- room_number → TID → データ
-- 同様に2段階だが、TID は固定長で高速
 ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓
      子ノード群（最大100個）

改善点:
- 深さ: log₁₀₀(n) ≈ 3層（100万レコードの場合）
- 最大3回のI/O で済む
- 1ページ（16KB）に多くのキーを格納可能
- 範囲検索が高速（リーフノード連結）
```

#### B+木の詳細構造

```
MySQLのB+木構造（例：1000万レコード）:

レベル0（ルートノード）- 1ノード
┌─────────────────────────────────────────────────────┐
│ [1000|5000|10000|50000|100000|500000|1000000]      │
│  ↓     ↓     ↓      ↓       ↓       ↓        ↓     │
└─────────────────────────────────────────────────────┘

レベル1（中間ノード）- 約100ノード
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│[100|200|300]│ │[5100|5200] │ │[10100|10200]│
│ ↓  ↓   ↓   │ │ ↓    ↓     │ │ ↓     ↓     │
└─────────────┘ └─────────────┘ └─────────────┘

レベル2（リーフノード）- 約10,000ノード
┌────────────────┐ ┌────────────────┐ ┌────────────────┐
│[1→行1|2→行2]   │ │[5101→行1000]   │ │[10101→行2000]  │
│[3→行3|4→行4]   │ │[5102→行1001]   │ │[10102→行2001]  │
│...            │ │...             │ │...             │
└────────────────┘ └────────────────┘ └────────────────┘
        ↓──────────────────↓──────────────────↓
        リーフノード同士は連結（範囲検索用）
```

**B+木の特徴：**

1. **完全平衡木**: すべてのリーフノードが同じ深さにある
2. **高い分岐度**: 1ページ（16KB）に多くのキーを格納
3. **効率的な範囲検索**: リーフノード間の連結により実現
4. **データ格納場所**: データはリーフノードのみに格納

### 1.3 MySQLのインデックス種類と実装

#### 1.3.1 Clustered Index（クラスタインデックス）

**定義**: 主キーのインデックスで、インデックスの順序 = データの物理的配置順序

```
クラスタインデックス構造:
┌─────────────────────────────────────────────────────┐
│                リーフノード                          │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│ │ Key: 100    │ │ Key: 200    │ │ Key: 300    │    │
│ │ Data: 全行  │ │ Data: 全行  │ │ Data: 全行  │    │
│ │ データ      │ │ データ      │ │ データ      │    │
│ └─────────────┘ └─────────────┘ └─────────────┘    │
└─────────────────────────────────────────────────────┘

特徴:
- 1回のI/Oで全てのデータを取得
- 主キーでの範囲検索が高速
- 挿入時のデータ移動が発生する可能性
```

#### 1.3.2 Secondary Index（セカンダリインデックス）

**定義**: 主キー以外のインデックス、リーフノードには主キー値のみ格納

```
セカンダリインデックス構造:
┌─────────────────────────────────────────────────────┐
│              セカンダリインデックス                  │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│ │ email_key   │ │ email_key   │ │ email_key   │    │
│ │ +主キー値   │ │ +主キー値   │ │ +主キー値   │    │
│ └─────────────┘ └─────────────┘ └─────────────┘    │
└─────────────────────────────────────────────────────┘
         ↓                ↓                ↓
┌─────────────────────────────────────────────────────┐
│               クラスタインデックス                   │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│ │ 主キー      │ │ 主キー      │ │ 主キー      │    │
│ │ +全データ   │ │ +全データ   │ │ +全データ   │    │
│ └─────────────┘ └─────────────┘ └─────────────┘    │
└─────────────────────────────────────────────────────┘

検索プロセス:
1. セカンダリインデックスで主キー値を取得
2. クラスタインデックスで実際のデータを取得
→ 2回のI/Oが必要
```

#### 1.3.3 Covering Index（カバリングインデックス）

**定義**: 必要なデータが全てインデックスに含まれている状態

```
通常のセカンダリインデックス:
CREATE INDEX idx_email ON users(email);

SELECT name, email FROM users WHERE email = 'test@example.com';
→ セカンダリインデックス + クラスタインデックス（2回のI/O）

カバリングインデックス:
CREATE INDEX idx_email_name ON users(email, name);

SELECT name, email FROM users WHERE email = 'test@example.com';
→ インデックスのみで完結（1回のI/O）

パフォーマンス向上:
- I/O回数: 2回 → 1回（50%削減）
- ディスクアクセス量: 大幅削減
- メモリ使用量: 削減
```

### 1.4 カーディナリティの実践的理解

#### カーディナリティの定義と影響

**カーディナリティ** = そのカラムの値の種類の絶対数

```
例：100万行のusersテーブル

高カーディナリティ（効果的）:
┌─────────────────────────────────────────────────────┐
│ user_id: 1,000,000種類の値                          │
│ → 1つの値につき平均1行                              │
│ → インデックスで大幅な絞り込み可能                  │
└─────────────────────────────────────────────────────┘

低カーディナリティ（要注意）:
┌─────────────────────────────────────────────────────┐
│ gender: 2種類の値（male, female）                   │
│ → 1つの値につき平均50万行                           │
│ → インデックスの効果は限定的                        │
└─────────────────────────────────────────────────────┘
```

#### 分布の偏りによる例外

**重要な例外**: 低カーディナリティでも分布が偏っている場合はインデックスが有効

```
例：ユーザーステータス
┌─────────────────────────────────────────────────────┐
│ status = 'active':   990,000行（99%）                │
│ status = 'deleted':   10,000行（1%）                 │
│ status = 'suspended':     100行（0.01%）             │
└─────────────────────────────────────────────────────┘

WHERE status = 'suspended'
→ 全体の0.01%のみ取得、インデックスが非常に効果的

WHERE status = 'active'
→ 全体の99%を取得、フルスキャンの方が高速
```

**MySQLの最適化：**

- オプティマイザーがカーディナリティと分布を考慮
- `ANALYZE TABLE`で統計情報を更新
- 必要に応じてインデックスヒントを使用

### 📖 参考資料

- [MySQL公式ドキュメント - InnoDB Index Types](https://dev.mysql.com/doc/refman/8.0/en/innodb-index-types.html)
- [MySQL公式ドキュメント - B-Tree Index](https://dev.mysql.com/doc/refman/8.0/en/mysql-indexes.html)

---

## 🏗 第2章: Terraformを使ったMySQL環境構築

### 2.1 プロジェクト構造の作成

```bash
mkdir mysql-dbre-training
cd mysql-dbre-training
```

Vimでファイルを作成していきます：

```bash
vim main.tf
```

### 2.2 Terraformメイン設定

**main.tf**

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# VPCネットワーク
resource "google_compute_network" "vpc_network" {
  name                    = "mysql-training-vpc"
  auto_create_subnetworks = false
}

# サブネット
resource "google_compute_subnetwork" "private_subnet" {
  name          = "mysql-private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "192.168.1.0/24"
  }
}

# Cloud SQL MySQL インスタンス
resource "google_sql_database_instance" "mysql_instance" {
  name             = "mysql-training-instance"
  database_version = "MYSQL_8_0"
  region          = var.region

  settings {
    tier              = "db-custom-2-4096"  # 2 vCPU, 4GB RAM
    disk_size         = 20
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      binary_log_enabled            = true
      backup_retention_settings {
        retained_backups = 7
      }
    }

    database_flags {
      name  = "slow_query_log"
      value = "on"
    }

    database_flags {
      name  = "long_query_time"
      value = "2"
    }

    database_flags {
      name  = "log_queries_not_using_indexes"
      value = "on"
    }

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.vpc_network.id
      authorized_networks {
        name  = "all"
        value = "0.0.0.0/0"  # 本番環境では制限すること
      }
    }
  }

  deletion_protection = false
}

# データベース作成
resource "google_sql_database" "training_db" {
  name     = "training_db"
  instance = google_sql_database_instance.mysql_instance.name
}

# ユーザー作成
resource "google_sql_user" "mysql_user" {
  name     = "training_user"
  instance = google_sql_database_instance.mysql_instance.name
  password = var.mysql_password
}

# Compute Engine インスタンス（クライアント用）
resource "google_compute_instance" "mysql_client" {
  name         = "mysql-client"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.private_subnet.name
    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = file("${path.module}/startup-script.sh")

  service_account {
    email = google_service_account.mysql_client_sa.email
    scopes = ["cloud-platform"]
  }
}

# サービスアカウント
resource "google_service_account" "mysql_client_sa" {
  account_id   = "mysql-client-sa"
  display_name = "MySQL Client Service Account"
}

# IAM binding
resource "google_project_iam_member" "mysql_client_sql_admin" {
  project = var.project_id
  role    = "roles/cloudsql.admin"
  member  = "serviceAccount:${google_service_account.mysql_client_sa.email}"
}
```

### 2.3 変数設定

```bash
vim variables.tf
```

**variables.tf**

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "Google Cloud zone"
  type        = string
  default     = "asia-northeast1-a"
}

variable "mysql_password" {
  description = "MySQL user password"
  type        = string
  sensitive   = true
}
```

### 2.4 出力設定

```bash
vim outputs.tf
```

**outputs.tf**

```hcl
output "mysql_instance_ip" {
  description = "MySQL instance IP address"
  value       = google_sql_database_instance.mysql_instance.public_ip_address
}

output "mysql_instance_connection_name" {
  description = "MySQL instance connection name"
  value       = google_sql_database_instance.mysql_instance.connection_name
}

output "client_instance_ip" {
  description = "Client instance external IP"
  value       = google_compute_instance.mysql_client.network_interface[0].access_config[0].nat_ip
}
```

### 2.5 スタートアップスクリプト

```bash
vim startup-script.sh
```

**startup-script.sh**

```bash
#!/bin/bash

# システム更新
apt-get update
apt-get upgrade -y

# MySQL Client インストール
apt-get install -y mysql-client-8.0

# k6 インストール
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
apt-get update
apt-get install k6

# 監視ツールインストール
apt-get install -y htop iotop sysstat

# Cloud SQL Proxy インストール
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
chmod +x cloud_sql_proxy
mv cloud_sql_proxy /usr/local/bin/

# vim設定（基本的な設定のみ）
cat > /etc/vim/vimrc.local << 'EOF'
syntax on
set number
set tabstop=4
set shiftwidth=4
set expandtab
set hlsearch
set incsearch
EOF

echo "Setup completed" >> /var/log/startup-script.log
```

### 2.6 Terraform実行

```bash
# 設定ファイルの検証
terraform validate

# 実行計画の確認
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="mysql_password=SecurePassword123!"

# 実行
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="mysql_password=SecurePassword123!"
```

### 📖 参考資料

- [Google Cloud SQL Terraform Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance)
- [Cloud SQL MySQL フラグリファレンス](https://cloud.google.com/sql/docs/mysql/flags)

---

## 📊 第3章: サンプルデータベースの構築

### 3.1 クライアントインスタンスへの接続

```bash
# 外部IPアドレスを取得
CLIENT_IP=$(terraform output -raw client_instance_ip)

# SSH接続
gcloud compute ssh mysql-client --zone=asia-northeast1-a
```

### 3.2 Cloud SQL Proxyの起動

```bash
# バックグラウンドでプロキシ起動
cloud_sql_proxy -instances=YOUR_PROJECT_ID:asia-northeast1:mysql-training-instance=tcp:3306 &
```

### 3.3 MySQLへの接続とデータベース作成

```bash
mysql -h 127.0.0.1 -u training_user -p training_db
```

### 3.4 サンプルテーブルの作成

```sql
-- 部屋テーブル
CREATE TABLE rooms (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    room_type ENUM('single', 'double', 'suite') NOT NULL,
    price_per_night DECIMAL(10, 2) NOT NULL,
    max_guests INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ゲストテーブル
CREATE TABLE guests (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    registration_date DATE NOT NULL,
    guest_type ENUM('regular', 'vip', 'corporate') DEFAULT 'regular',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 予約テーブル（Qiitaの記事から参考）
CREATE TABLE room_reservations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    room_id INT NOT NULL,
    guest_id INT NOT NULL,
    guest_number INT NOT NULL DEFAULT 1,
    is_paid TINYINT(1) DEFAULT 0,
    reserved_at DATETIME(6) NOT NULL,
    canceled_at DATETIME(6) DEFAULT NULL,
    start_at DATETIME(6) NOT NULL,
    end_at DATETIME(6) NOT NULL,
    total_amount DECIMAL(10, 2),
    special_requests TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (room_id) REFERENCES rooms(id),
    FOREIGN KEY (guest_id) REFERENCES guests(id)
) ENGINE=InnoDB;

-- 支払いテーブル
CREATE TABLE payments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reservation_id INT NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    payment_method ENUM('cash', 'credit_card', 'bank_transfer') NOT NULL,
    payment_status ENUM('pending', 'completed', 'failed', 'refunded') DEFAULT 'pending',
    transaction_id VARCHAR(100),
    payment_date DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (reservation_id) REFERENCES room_reservations(id)
) ENGINE=InnoDB;
```

### 3.5 大量サンプルデータの生成

```sql
-- データ生成用のストアドプロシージャ
DELIMITER //

CREATE PROCEDURE GenerateTestData()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE j INT DEFAULT 1;
    DECLARE k INT DEFAULT 1;

    -- 部屋データ生成
    WHILE i <= 1000 DO
        INSERT INTO rooms (name, room_type, price_per_night, max_guests)
        VALUES
        (
            CONCAT('Room-', LPAD(i, 4, '0')),
            CASE MOD(i, 3)
                WHEN 0 THEN 'single'
                WHEN 1 THEN 'double'
                ELSE 'suite'
            END,
            ROUND(5000 + (RAND() * 20000), 2),
            CASE MOD(i, 3)
                WHEN 0 THEN 1
                WHEN 1 THEN 2
                ELSE 4
            END
        );
        SET i = i + 1;
    END WHILE;

    -- ゲストデータ生成
    WHILE j <= 100000 DO
        INSERT INTO guests (email, first_name, last_name, phone, registration_date, guest_type)
        VALUES
        (
            CONCAT('guest', j, '@example.com'),
            CONCAT('FirstName', j),
            CONCAT('LastName', j),
            CONCAT('090-', LPAD(FLOOR(RAND() * 100000000), 8, '0')),
            DATE_SUB(CURRENT_DATE, INTERVAL FLOOR(RAND() * 1000) DAY),
            CASE MOD(j, 10)
                WHEN 0 THEN 'vip'
                WHEN 9 THEN 'corporate'
                ELSE 'regular'
            END
        );
        SET j = j + 1;

        -- 大量データ処理のためのコミット
        IF MOD(j, 1000) = 0 THEN
            COMMIT;
        END IF;
    END WHILE;

    -- 予約データ生成（500万件）
    WHILE k <= 5000000 DO
        SET @room_id = FLOOR(1 + (RAND() * 1000));
        SET @guest_id = FLOOR(1 + (RAND() * 100000));
        SET @start_date = DATE_ADD('2020-01-01', INTERVAL FLOOR(RAND() * 1500) DAY);
        SET @end_date = DATE_ADD(@start_date, INTERVAL (1 + FLOOR(RAND() * 7)) DAY);

        INSERT INTO room_reservations
        (room_id, guest_id, guest_number, is_paid, reserved_at, start_at, end_at, total_amount)
        VALUES
        (
            @room_id,
            @guest_id,
            1 + FLOOR(RAND() * 4),
            IF(RAND() > 0.1, 1, 0),  -- 90%が支払済み
            DATE_SUB(@start_date, INTERVAL FLOOR(RAND() * 30) DAY),
            @start_date,
            @end_date,
            ROUND((DATEDIFF(@end_date, @start_date) * (5000 + RAND() * 20000)), 2)
        );

        SET k = k + 1;

        -- メモリ使用量を抑制
        IF MOD(k, 10000) = 0 THEN
            COMMIT;
            SELECT CONCAT('Generated ', k, ' reservations') AS progress;
        END IF;
    END WHILE;

    SELECT 'Test data generation completed!' AS result;
END //

DELIMITER ;

-- プロシージャ実行（時間がかかります）
CALL GenerateTestData();
```

### 📖 参考資料

- [MySQL 8.0 データ型リファレンス](https://dev.mysql.com/doc/refman/8.0/en/data-types.html)
- [MySQL 8.0 ストアドプロシージャ](https://dev.mysql.com/doc/refman/8.0/en/stored-programs.html)

---

## 🔍 第4章: パフォーマンス分析の基礎

### 4.1 なぜパフォーマンス分析が重要なのか？

データベースのパフォーマンス問題は、システム全体の応答速度に直結します。しかし、**「どこに問題があるのか？」**を正確に特定するには、体系的な分析手法が必要です。

**パフォーマンス問題の典型的な原因：**

```
パフォーマンス問題の階層構造:
┌─────────────────────────────────────────────────────┐
│                アプリケーション層                    │
│ ・N+1問題                                           │
│ ・無駄な重複クエリ                                  │
│ ・コネクションプール不足                            │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│                   SQL層                             │
│ ・インデックス不足                                  │
│ ・非効率なJOIN                                      │
│ ・不適切なWHERE条件                                 │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│                ストレージ層                         │
│ ・バッファプール不足                                │
│ ・ディスクI/Oボトルネック                           │
│ ・ロック競合                                        │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│                インフラ層                           │
│ ・CPU/メモリ不足                                    │
│ ・ディスク性能                                      │
│ ・ネットワーク遅延                                  │
└─────────────────────────────────────────────────────┘
```

### 4.2 スロークエリログの理論と実践

#### 4.2.1 スロークエリログの仕組み

MySQLは各クエリの実行時間を監視し、閾値を超えたクエリを記録します：

```
クエリ実行フロー:
┌─────────────────────────────────────────────────────┐
│ 1. クエリ受信                                       │
│ 2. 実行開始時刻記録                                 │
│ 3. クエリ実行                                       │
│ 4. 実行終了時刻記録                                 │
│ 5. 実行時間計算                                     │
│ 6. long_query_timeと比較                            │
│ 7. 閾値超過の場合 → スロークエリログに記録         │
└─────────────────────────────────────────────────────┘
```

**設定の確認と調整：**

```sql
-- 現在の設定確認
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time';

-- スロークエリログの確認
SHOW GLOBAL STATUS LIKE 'Slow_queries';

-- 設定の意味:
-- slow_query_log: ON/OFF
-- long_query_time: 閾値（秒）- 2秒が一般的
-- log_queries_not_using_indexes: インデックス未使用クエリも記録
```

#### 4.2.2 スロークエリログの分析パターン

**典型的なスロークエリパターン：**

```sql
-- パターン1: インデックス未使用
SELECT * FROM large_table WHERE non_indexed_column = 'value';
-- → フルテーブルスキャン

-- パターン2: 非効率なJOIN
SELECT * FROM table1 t1
JOIN table2 t2 ON t1.column = t2.column
WHERE t1.date > '2024-01-01';
-- → JOINの順序が最適化されていない

-- パターン3: 不適切なソート
SELECT * FROM users ORDER BY non_indexed_column LIMIT 10;
-- → Using filesortが発生

-- パターン4: 複雑なサブクエリ
SELECT * FROM users WHERE id IN (
    SELECT user_id FROM orders WHERE order_date > '2024-01-01'
);
-- → 非効率なサブクエリ実行
```

### 4.3 パフォーマンススキーマの活用

#### 4.3.1 Performance Schemaの内部構造

MySQL 8.0の**Performance Schema**は、実行時統計情報を収集する強力なツールです：

```
Performance Schema の構造:
┌─────────────────────────────────────────────────────┐
│                   イベント収集                       │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│ │ SQL文実行   │ │ ファイルI/O │ │ ロック待機  │    │
│ │ イベント    │ │ イベント    │ │ イベント    │    │
│ └─────────────┘ └─────────────┘ └─────────────┘    │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│                   集約・分析                         │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│ │ 文別統計    │ │ テーブル別  │ │ ユーザー別  │    │
│ │ 情報        │ │ 統計情報    │ │ 統計情報    │    │
│ └─────────────┘ └─────────────┘ └─────────────┘    │
└─────────────────────────────────────────────────────┘
```

#### 4.3.2 実践的なパフォーマンス分析クエリ

**重要な分析クエリ：**

```sql
-- 最も時間のかかるクエリの特定
SELECT
    digest_text,
    count_star AS exec_count,
    ROUND(avg_timer_wait/1000000000000, 2) AS avg_time_sec,
    ROUND(max_timer_wait/1000000000000, 2) AS max_time_sec,
    sum_rows_examined,
    sum_rows_sent
FROM performance_schema.events_statements_summary_by_digest
WHERE digest_text IS NOT NULL
ORDER BY avg_timer_wait DESC
LIMIT 10;

-- テーブルスキャンを実行しているクエリ
SELECT
    digest_text,
    count_star,
    sum_rows_examined,
    sum_rows_sent,
    ROUND(sum_rows_examined/sum_rows_sent, 2) AS examine_to_send_ratio
FROM performance_schema.events_statements_summary_by_digest
WHERE sum_rows_examined > sum_rows_sent * 100
AND count_star > 10
ORDER BY sum_rows_examined DESC
LIMIT 10;
```

### 4.3 sys スキーマによる分析

MySQL 8.0の**sys スキーマ**はパフォーマンス分析を簡単にします。

```sql
-- フルテーブルスキャンを実行しているクエリ
SELECT
    query,
    exec_count,
    total_latency,
    rows_examined_avg,
    last_seen
FROM sys.statements_with_full_table_scans
ORDER BY total_latency DESC
LIMIT 10;

-- 使用されていないインデックス
SELECT * FROM sys.schema_unused_indexes;

-- 冗長なインデックス
SELECT * FROM sys.schema_redundant_indexes;

-- テーブル統計情報
SELECT * FROM sys.schema_table_statistics
WHERE table_schema = 'training_db'
ORDER BY total_latency DESC;
```

### 📖 参考資料

- [MySQL 8.0 Performance Schema](https://dev.mysql.com/doc/refman/8.0/en/performance-schema.html)
- [MySQL 8.0 sys Schema](https://dev.mysql.com/doc/refman/8.0/en/sys-schema.html)

---

## 🎯 第5章: EXPLAIN分析とインデックス最適化

### 5.1 EXPLAINの理論的背景

#### 5.1.1 クエリオプティマイザの動作原理

MySQLは受信したクエリを**クエリオプティマイザ**が分析し、最適な実行計画を生成します。EXPLAINは、この実行計画を人間が理解できる形で表示するツールです。

```
クエリ最適化プロセス:
┌─────────────────────────────────────────────────────┐
│ 1. SQL文解析（パーサー）                            │
│    ↓                                                │
│ 2. 統計情報取得                                     │
│    ・テーブル行数                                   │
│    ・インデックス統計                               │
│    ・カーディナリティ                               │
│    ↓                                                │
│ 3. 実行計画候補の生成                               │
│    ・インデックス選択                               │
│    ・JOIN順序決定                                   │
│    ・アクセス方法選択                               │
│    ↓                                                │
│ 4. コスト計算                                       │
│    ・I/Oコスト                                      │
│    ・CPUコスト                                      │
│    ・メモリコスト                                   │
│    ↓                                                │
│ 5. 最適計画選択                                     │
└─────────────────────────────────────────────────────┘
```

#### 5.1.2 EXPLAINの出力形式

```sql
-- 基本的なEXPLAIN（テーブル形式）
EXPLAIN SELECT * FROM room_reservations WHERE guest_id = 1000;

-- 詳細なJSON形式（より多くの情報）
EXPLAIN FORMAT=JSON SELECT * FROM room_reservations WHERE guest_id = 1000;

-- 実際の実行統計（MySQL 8.0.18以降）
EXPLAIN ANALYZE SELECT * FROM room_reservations WHERE guest_id = 1000;
```

### 5.2 EXPLAINの詳細解析

#### 5.2.1 重要項目の理論的理解

| 項目         | 意味                   | 重要度 | 理論的背景                         |
| ------------ | ---------------------- | ------ | ---------------------------------- |
| **type**     | アクセスタイプ         | ⭐⭐⭐ | データ取得の効率性を示す最重要指標 |
| **rows**     | 検索対象行数           | ⭐⭐⭐ | I/Oコストの予測値                  |
| **key**      | 使用されたインデックス | ⭐⭐⭐ | アクセスパスの効率性               |
| **Extra**    | 付加情報               | ⭐⭐⭐ | 追加処理の有無とコスト             |
| **filtered** | WHERE句での絞り込み率  | ⭐⭐   | セレクティビティの指標             |

#### 5.2.2 typeの値の詳細解説（効率性順）

**1. const（最高効率）**

```sql
-- 主キーまたはユニークインデックスでの定数検索
SELECT * FROM users WHERE id = 123;

理論的背景:
- B+木の最大深度回のI/Oで確実に1行を特定
- 計算量: O(log n)
- 実際のI/O: 通常3-4回で完了
```

**2. eq_ref（非常に高効率）**

```sql
-- JOINでの主キー・ユニーク検索
SELECT * FROM orders o
JOIN users u ON o.user_id = u.id;

理論的背景:
- JOIN相手テーブルから最大1行を取得
- 外部表の各行に対して内部表を1回だけアクセス
- 1:1関係での最適なJOIN方法
```

**3. ref（高効率）**

```sql
-- 非ユニークインデックスでの等価検索
SELECT * FROM orders WHERE status = 'pending';

理論的背景:
- インデックスを使用するが複数行を返す可能性
- セレクティビティ（絞り込み率）が重要
- カーディナリティが高いほど効率的
```

**4. range（中効率）**

```sql
-- インデックスでの範囲検索
SELECT * FROM orders WHERE order_date BETWEEN '2024-01-01' AND '2024-01-31';

理論的背景:
- インデックスの特定範囲をスキャン
- 開始点をB+木で特定、終了点まで順次読み取り
- 範囲が狭いほど効率的
```

**5. index（低効率）**

```sql
-- フルインデックススキャン
SELECT id FROM orders ORDER BY id;

理論的背景:
- インデックス全体をスキャン
- データファイルよりもサイズが小さいため、ALLより高速
- カバリングインデックスの場合は効果的
```

**6. ALL（最低効率）**

```sql
-- フルテーブルスキャン
SELECT * FROM orders WHERE description LIKE '%keyword%';

理論的背景:
- 全行を順次チェック
- 最も多くのI/Oが発生
- 小さなテーブルでは逆に効率的な場合もある
```

#### 5.2.3 Extraの重要な値の詳細解説

**Using index（カバリングインデックス）**

```sql
-- インデックスのみでクエリが完結
SELECT user_id, order_date FROM orders WHERE user_id = 123;

理論的背景:
- 必要なデータが全てインデックス内に存在
- データページへのアクセス不要
- I/O回数が大幅に削減される
```

**Using where**

```sql
-- インデックス後にWHERE条件を適用
SELECT * FROM orders WHERE user_id = 123 AND amount > 1000;

理論的背景:
- インデックスで絞り込み後、追加条件をフィルタリング
- インデックスだけでは完全に条件を満たせない状況
- 複合インデックスの最適化余地がある
```

**Using filesort（ソート処理）**

```sql
-- ソート処理が必要
SELECT * FROM orders ORDER BY amount DESC;

理論的背景:
- インデックスの順序とソート順序が一致しない
- 一時的なソート処理が必要
- メモリ内ソートまたはディスクソートが発生
```

**Using temporary（一時テーブル）**

```sql
-- 一時テーブルが必要
SELECT user_id, COUNT(*) FROM orders GROUP BY user_id;

理論的背景:
- 中間結果を格納するための一時テーブル作成
- GROUP BY、ORDER BY、DISTINCT等で発生
- メモリまたはディスクに一時テーブルを作成
```

### 5.3 実行計画の読み方の実践

#### 5.3.1 実行計画の読み取り順序

```sql
-- 複雑なクエリの例
SELECT u.name, COUNT(o.id) as order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.created_at > '2024-01-01'
GROUP BY u.id, u.name
ORDER BY order_count DESC;
```

**EXPLAIN出力の読み方：**

```
実行計画の読み取りルール:
1. idが同じ場合：上から下へ実行
2. idが異なる場合：大きい数字から実行
3. サブクエリ：内側から外側へ実行
4. JOINの順序：最初に出現するテーブルが駆動表
```

#### 5.3.2 コスト計算の理解

MySQLのオプティマイザは以下の要素でコストを計算します：

```
コスト計算の要素:
┌─────────────────────────────────────────────────────┐
│ I/Oコスト                                           │
│ ・ページ読み込み: 1.0                               │
│ ・ランダムアクセス: 高コスト                        │
│ ・シーケンシャルアクセス: 低コスト                  │
└─────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────┐
│ CPUコスト                                           │
│ ・行評価: 0.2                                       │
│ ・条件判定: 0.1                                     │
│ ・ソート: 行数 × log(行数) × 0.001                 │
└─────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────┐
│ メモリコスト                                        │
│ ・一時テーブル作成                                  │
│ ・バッファプール使用量                              │
│ ・ソート領域使用量                                  │
└─────────────────────────────────────────────────────┘
```

### 5.3 実践: インデックス最適化

#### ケース1: インデックスが全く当たっていない

```sql
-- 問題のあるクエリ
EXPLAIN SELECT * FROM room_reservations WHERE guest_id = 50000;

-- インデックス追加
ALTER TABLE room_reservations ADD INDEX idx_guest_id (guest_id);

-- 改善確認
EXPLAIN SELECT * FROM room_reservations WHERE guest_id = 50000;
```

#### ケース2: 複合インデックスの順序問題

```sql
-- 複合インデックス作成
ALTER TABLE room_reservations ADD INDEX idx_room_guest (room_id, guest_id);

-- 順序が正しい場合（高速）
EXPLAIN SELECT * FROM room_reservations WHERE room_id = 100 AND guest_id = 1000;

-- 順序が間違っている場合（低速）
EXPLAIN SELECT * FROM room_reservations WHERE guest_id = 1000;

-- 改善策: 別のインデックス追加
ALTER TABLE room_reservations ADD INDEX idx_guest_room (guest_id, room_id);
```

#### ケース3: ソートに適用できないインデックス

```sql
-- 問題のあるクエリ（Using filesort発生）
EXPLAIN SELECT * FROM room_reservations
WHERE room_id = 100
ORDER BY reserved_at DESC
LIMIT 10;

-- ソート対応インデックス追加
ALTER TABLE room_reservations ADD INDEX idx_room_reserved (room_id, reserved_at);

-- 改善確認
EXPLAIN SELECT * FROM room_reservations
WHERE room_id = 100
ORDER BY reserved_at DESC
LIMIT 10;
```

#### ケース4: 複合インデックスでの範囲検索問題

```sql
-- 範囲検索が最初にある場合（非効率）
ALTER TABLE room_reservations ADD INDEX idx_reserved_room (reserved_at, room_id);

EXPLAIN SELECT * FROM room_reservations
WHERE reserved_at > '2023-01-01' AND room_id = 100;

-- 改善: 等価検索を先にする
ALTER TABLE room_reservations ADD INDEX idx_room_reserved_opt (room_id, reserved_at);

EXPLAIN SELECT * FROM room_reservations
WHERE reserved_at > '2023-01-01' AND room_id = 100;
```

### 5.4 カバリングインデックスの活用

```sql
-- カバリングインデックス作成
ALTER TABLE room_reservations
ADD INDEX idx_guest_covering (guest_id, is_paid, reserved_at, room_id);

-- Using indexが表示される（高速）
EXPLAIN SELECT guest_id, is_paid, reserved_at, room_id
FROM room_reservations
WHERE guest_id = 1000;
```

### 📖 参考資料

- [MySQL 8.0 EXPLAIN Statement](https://dev.mysql.com/doc/refman/8.0/en/explain.html)
- [MySQL 8.0 Index Optimization](https://dev.mysql.com/doc/refman/8.0/en/optimization-indexes.html)

---

## ⚡ 第6章: k6を使った負荷テストとベンチマーク

### 6.1 k6テストスクリプトの作成

```bash
vim mysql-load-test.js
```

**mysql-load-test.js**

```javascript
import { check } from "k6";
import sql from "k6/x/sql";

// データベース接続設定
const db = sql.open(
  "mysql",
  "training_user:SecurePassword123!@tcp(127.0.0.1:3306)/training_db",
);

export let options = {
  stages: [
    { duration: "2m", target: 10 }, // ramp up to 10 users
    { duration: "5m", target: 10 }, // stay at 10 users
    { duration: "2m", target: 20 }, // ramp up to 20 users
    { duration: "5m", target: 20 }, // stay at 20 users
    { duration: "2m", target: 0 }, // ramp down to 0 users
  ],
  thresholds: {
    sql_query_duration: ["p(95)<1000"], // 95%のクエリが1秒以内
    checks: ["rate>0.9"], // 90%以上成功
  },
};

export default function () {
  // ランダムなゲストIDを生成
  let guestId = Math.floor(Math.random() * 100000) + 1;
  let roomId = Math.floor(Math.random() * 1000) + 1;

  // テストケース1: インデックスを使った検索
  let result1 = sql.query(
    db,
    "SELECT COUNT(*) as count FROM room_reservations WHERE guest_id = ?",
    guestId,
  );

  check(result1, {
    "guest search returns result": (r) => r.length > 0,
  });

  // テストケース2: 複合インデックスを使った検索
  let result2 = sql.query(
    db,
    "SELECT id, guest_number, reserved_at FROM room_reservations WHERE room_id = ? AND is_paid = 1 LIMIT 10",
    roomId,
  );

  check(result2, {
    "room search returns result": (r) => r.length >= 0,
  });

  // テストケース3: JOIN クエリ
  let result3 = sql.query(
    db,
    `
        SELECT r.name, rr.reserved_at, g.first_name, g.last_name 
        FROM room_reservations rr
        JOIN rooms r ON rr.room_id = r.id
        JOIN guests g ON rr.guest_id = g.id
        WHERE rr.reserved_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        LIMIT 5
    `,
  );

  check(result3, {
    "join query returns result": (r) => r.length >= 0,
  });
}

export function teardown() {
  db.close();
}
```

### 6.2 基本的な負荷テスト実行

```bash
# 基本実行
k6 run mysql-load-test.js

# より詳細な出力
k6 run --out json=load-test-results.json mysql-load-test.js

# 結果ファイルの確認
cat load-test-results.json | jq '.metrics'
```

### 6.3 シナリオ別負荷テスト

#### シナリオ1: インデックスなしの性能測定

```bash
vim no-index-test.js
```

```javascript
import { check } from "k6";
import sql from "k6/x/sql";

const db = sql.open(
  "mysql",
  "training_user:SecurePassword123!@tcp(127.0.0.1:3306)/training_db",
);

export let options = {
  vus: 5, // 5 virtual users
  duration: "30s", // test for 30 seconds
};

export function setup() {
  // テスト用インデックスを削除
  sql.query(db, "DROP INDEX IF EXISTS idx_guest_id ON room_reservations");
  sql.query(db, "DROP INDEX IF EXISTS idx_room_guest ON room_reservations");
  console.log("Indexes dropped for baseline test");
}

export default function () {
  let guestId = Math.floor(Math.random() * 100000) + 1;

  let result = sql.query(
    db,
    "SELECT COUNT(*) as count FROM room_reservations WHERE guest_id = ?",
    guestId,
  );

  check(result, {
    "query completed": (r) => r.length > 0,
  });
}

export function teardown() {
  db.close();
}
```

#### シナリオ2: インデックスありの性能測定

```bash
vim with-index-test.js
```

```javascript
import { check } from "k6";
import sql from "k6/x/sql";

const db = sql.open(
  "mysql",
  "training_user:SecurePassword123!@tcp(127.0.0.1:3306)/training_db",
);

export let options = {
  vus: 5,
  duration: "30s",
};

export function setup() {
  // インデックス作成
  sql.query(
    db,
    "ALTER TABLE room_reservations ADD INDEX idx_guest_id (guest_id)",
  );
  sql.query(
    db,
    "ALTER TABLE room_reservations ADD INDEX idx_room_guest (room_id, guest_id)",
  );
  console.log("Indexes created for optimized test");
}

export default function () {
  let guestId = Math.floor(Math.random() * 100000) + 1;

  let result = sql.query(
    db,
    "SELECT COUNT(*) as count FROM room_reservations WHERE guest_id = ?",
    guestId,
  );

  check(result, {
    "query completed": (r) => r.length > 0,
  });
}

export function teardown() {
  db.close();
}
```

### 6.4 リアルタイム監視テスト

```bash
vim real-time-monitoring.js
```

```javascript
import { check } from "k6";
import sql from "k6/x/sql";

const db = sql.open(
  "mysql",
  "training_user:SecurePassword123!@tcp(127.0.0.1:3306)/training_db",
);

export let options = {
  stages: [
    { duration: "1m", target: 50 },
    { duration: "3m", target: 50 },
    { duration: "1m", target: 0 },
  ],
  thresholds: {
    http_req_duration: ["p(95)<2000"],
    checks: ["rate>0.95"],
  },
};

export default function () {
  // 重いクエリのシミュレーション
  let result = sql.query(
    db,
    `
        SELECT 
            r.name,
            COUNT(rr.id) as reservation_count,
            AVG(rr.total_amount) as avg_amount
        FROM rooms r
        LEFT JOIN room_reservations rr ON r.id = rr.room_id
        WHERE rr.reserved_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
        GROUP BY r.id, r.name
        HAVING COUNT(rr.id) > 5
        ORDER BY reservation_count DESC
        LIMIT 20
    `,
  );

  check(result, {
    "complex query completed": (r) => r.length >= 0,
  });
}
```

### 6.5 結果分析とレポート

```bash
# 詳細なJSONレポート生成
k6 run --out json=detailed-results.json mysql-load-test.js

# HTMLレポート生成（k6のプラグイン使用）
k6 run --out web-dashboard mysql-load-test.js
```

### 📖 参考資料

- [k6 公式ドキュメント](https://k6.io/docs/)
- [k6 MySQL Extension](https://github.com/grafana/xk6-sql)

---

## 📊 第7章: Google Cloud Monitoringによる監視

### 7.1 Cloud SQL監視メトリクスの設定

Google CloudコンソールでCloud SQL インスタンスの監視を設定します。

#### 重要な監視メトリクス

1. **CPU使用率**
2. **メモリ使用率**
3. **ディスクI/O**
4. **接続数**
5. **クエリ実行時間**
6. **レプリケーション遅延**

### 7.2 カスタムメトリクスの作成

```bash
vim monitoring-script.sh
```

**monitoring-script.sh**

```bash
#!/bin/bash

# MySQL接続情報
MYSQL_HOST="127.0.0.1"
MYSQL_USER="training_user"
MYSQL_PASSWORD="SecurePassword123!"
MYSQL_DB="training_db"

# メトリクス収集関数
collect_mysql_metrics() {
    echo "=== MySQL Status Metrics ==="
    echo "Timestamp: $(date)"

    # 接続数
    CONNECTIONS=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "SHOW STATUS LIKE 'Threads_connected';" --skip-column-names | awk '{print $2}')
    echo "Active Connections: $CONNECTIONS"

    # スロークエリ数
    SLOW_QUERIES=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "SHOW STATUS LIKE 'Slow_queries';" --skip-column-names | awk '{print $2}')
    echo "Slow Queries: $SLOW_QUERIES"

    # バッファプール使用率
    BUFFER_POOL_USAGE=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "
        SELECT ROUND((1 - (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_free') /
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total')) * 100, 2) AS buffer_pool_usage_percent;
    " --skip-column-names)
    echo "Buffer Pool Usage: $BUFFER_POOL_USAGE%"

    # 最も実行時間の長いクエリ
    echo "=== Top 5 Slowest Queries ==="
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "
        SELECT
            LEFT(digest_text, 100) as query_preview,
            count_star as exec_count,
            ROUND(avg_timer_wait/1000000000000, 2) as avg_time_sec
        FROM performance_schema.events_statements_summary_by_digest
        WHERE digest_text IS NOT NULL
        ORDER BY avg_timer_wait DESC
        LIMIT 5;
    "

    echo "========================================="
}

# 監視実行
while true; do
    collect_mysql_metrics
    sleep 60  # 60秒ごとに実行
done
```

### 7.3 アラート設定

```bash
vim create-alerts.sh
```

**create-alerts.sh**

```bash
#!/bin/bash

PROJECT_ID="YOUR_PROJECT_ID"
INSTANCE_NAME="mysql-training-instance"

# CPU使用率アラート
gcloud alpha monitoring policies create --policy-from-file=- <<EOF
{
  "displayName": "MySQL High CPU Usage",
  "conditions": [
    {
      "displayName": "CPU usage is above 80%",
      "conditionThreshold": {
        "filter": "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"$PROJECT_ID:$INSTANCE_NAME\"",
        "comparison": "COMPARISON_ABOVE_THRESHOLD",
        "thresholdValue": 0.8,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN",
            "crossSeriesReducer": "REDUCE_MEAN"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "notificationRateLimit": {
      "period": "300s"
    }
  },
  "enabled": true
}
EOF

# 接続数アラート
gcloud alpha monitoring policies create --policy-from-file=- <<EOF
{
  "displayName": "MySQL High Connection Count",
  "conditions": [
    {
      "displayName": "Connection count is above 100",
      "conditionThreshold": {
        "filter": "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/network/connections\"",
        "comparison": "COMPARISON_ABOVE_THRESHOLD",
        "thresholdValue": 100,
        "duration": "180s"
      }
    }
  ],
  "enabled": true
}
EOF
```

### 📖 参考資料

- [Cloud SQL Monitoring](https://cloud.google.com/sql/docs/mysql/monitor-instance)
- [Cloud Monitoring](https://cloud.google.com/monitoring/docs)

---

## 🔄 第8章: MySQLバージョンアップとマイグレーション

### 8.1 MySQL 8.0から8.4へのバージョンアップ

#### 8.1.1 事前チェック

```sql
-- バージョン確認
SELECT VERSION();

-- 廃止予定機能の使用チェック
SHOW WARNINGS;

-- パフォーマンススキーマの確認
SELECT * FROM performance_schema.setup_instruments
WHERE name LIKE '%deprecated%' AND enabled = 'YES';
```

#### 8.1.2 バックアップの実行

```bash
# mysqldumpによるバックアップ
mysqldump -h 127.0.0.1 -u training_user -p training_db > backup_before_upgrade.sql

# Cloud SQLの自動バックアップ確認
gcloud sql backups list --instance=mysql-training-instance
```

#### 8.1.3 Terraformでのバージョンアップ

```bash
vim main.tf
```

```hcl
# main.tfのdatabase_versionを更新
resource "google_sql_database_instance" "mysql_instance" {
  # 前略
  database_version = "MYSQL_8_0_34"  # 最新の8.0系に更新

  settings {
    # メンテナンスウィンドウの設定
    maintenance_window {
      hour         = 3
      day          = 7  # 日曜日
      update_track = "stable"
    }
    # 後略
  }
}
```

```bash
# 更新実行
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="mysql_password=SecurePassword123!"
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="mysql_password=SecurePassword123!"
```

#### 8.1.4 アップグレード後のチェック

```sql
-- バージョン確認
SELECT VERSION();

-- エラーログ確認
SHOW GLOBAL STATUS LIKE 'Error%';

-- 統計情報の更新
ANALYZE TABLE room_reservations;
ANALYZE TABLE rooms;
ANALYZE TABLE guests;
ANALYZE TABLE payments;

-- パフォーマンス比較
SELECT
    digest_text,
    count_star,
    ROUND(avg_timer_wait/1000000000000, 2) as avg_time_sec
FROM performance_schema.events_statements_summary_by_digest
ORDER BY avg_timer_wait DESC
LIMIT 10;
```

### 8.2 MySQL → PostgreSQLマイグレーション体験

#### 8.2.1 PostgreSQLインスタンスの作成

```bash
vim postgres-instance.tf
```

**postgres-instance.tf**

```hcl
resource "google_sql_database_instance" "postgres_instance" {
  name             = "postgres-training-instance"
  database_version = "POSTGRES_15"
  region          = var.region

  settings {
    tier              = "db-custom-2-4096"
    disk_size         = 20
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled = true
      authorized_networks {
        name  = "all"
        value = "0.0.0.0/0"
      }
    }
  }

  deletion_protection = false
}

resource "google_sql_database" "postgres_training_db" {
  name     = "training_db"
  instance = google_sql_database_instance.postgres_instance.name
}

resource "google_sql_user" "postgres_user" {
  name     = "training_user"
  instance = google_sql_database_instance.postgres_instance.name
  password = var.postgres_password
}
```

#### 8.2.2 データ構造のマッピング

```sql
-- PostgreSQL用のテーブル作成スクリプト
-- rooms table
CREATE TABLE rooms (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    room_type VARCHAR(20) CHECK (room_type IN ('single', 'double', 'suite')) NOT NULL,
    price_per_night DECIMAL(10, 2) NOT NULL,
    max_guests INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- guests table
CREATE TABLE guests (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    registration_date DATE NOT NULL,
    guest_type VARCHAR(20) DEFAULT 'regular' CHECK (guest_type IN ('regular', 'vip', 'corporate')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- room_reservations table
CREATE TABLE room_reservations (
    id SERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL REFERENCES rooms(id),
    guest_id INTEGER NOT NULL REFERENCES guests(id),
    guest_number INTEGER NOT NULL DEFAULT 1,
    is_paid BOOLEAN DEFAULT FALSE,
    reserved_at TIMESTAMP NOT NULL,
    canceled_at TIMESTAMP DEFAULT NULL,
    start_at TIMESTAMP NOT NULL,
    end_at TIMESTAMP NOT NULL,
    total_amount DECIMAL(10, 2),
    special_requests TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- インデックス作成
CREATE INDEX idx_guest_id ON room_reservations (guest_id);
CREATE INDEX idx_room_id ON room_reservations (room_id);
CREATE INDEX idx_room_reserved ON room_reservations (room_id, reserved_at);
```

#### 8.2.3 データ移行スクリプト

```bash
vim mysql_to_postgres_migration.py
```

**mysql_to_postgres_migration.py**

```python
#!/usr/bin/env python3
import mysql.connector
import psycopg2
import psycopg2.extras
from datetime import datetime
import logging

# ログ設定
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# 接続設定
MYSQL_CONFIG = {
    'host': '127.0.0.1',
    'port': 3306,
    'user': 'training_user',
    'password': 'SecurePassword123!',
    'database': 'training_db'
}

POSTGRES_CONFIG = {
    'host': 'POSTGRES_INSTANCE_IP',
    'port': 5432,
    'user': 'training_user',
    'password': 'SecurePassword123!',
    'database': 'training_db'
}

def migrate_table(table_name, mysql_conn, postgres_conn, batch_size=1000):
    """テーブルデータの移行"""
    logger.info(f"Starting migration for table: {table_name}")

    mysql_cursor = mysql_conn.cursor(dictionary=True)
    postgres_cursor = postgres_conn.cursor()

    # 総行数の取得
    mysql_cursor.execute(f"SELECT COUNT(*) as count FROM {table_name}")
    total_rows = mysql_cursor.fetchone()['count']
    logger.info(f"Total rows to migrate: {total_rows}")

    # バッチでデータを移行
    offset = 0
    migrated_rows = 0

    while offset < total_rows:
        # MySQLからデータ取得
        query = f"SELECT * FROM {table_name} LIMIT {batch_size} OFFSET {offset}"
        mysql_cursor.execute(query)
        rows = mysql_cursor.fetchall()

        if not rows:
            break

        # PostgreSQLに挿入
        if table_name == 'rooms':
            insert_rooms(rows, postgres_cursor)
        elif table_name == 'guests':
            insert_guests(rows, postgres_cursor)
        elif table_name == 'room_reservations':
            insert_reservations(rows, postgres_cursor)

        postgres_conn.commit()
        migrated_rows += len(rows)
        offset += batch_size

        logger.info(f"Migrated {migrated_rows}/{total_rows} rows")

    logger.info(f"Migration completed for table: {table_name}")

def insert_rooms(rows, cursor):
    """roomsテーブルのデータ挿入"""
    for row in rows:
        cursor.execute("""
            INSERT INTO rooms (name, room_type, price_per_night, max_guests, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (
            row['name'], row['room_type'], row['price_per_night'],
            row['max_guests'], row['created_at'], row['updated_at']
        ))

def insert_guests(rows, cursor):
    """guestsテーブルのデータ挿入"""
    for row in rows:
        cursor.execute("""
            INSERT INTO guests (email, first_name, last_name, phone, registration_date,
                              guest_type, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            row['email'], row['first_name'], row['last_name'], row['phone'],
            row['registration_date'], row['guest_type'], row['created_at'], row['updated_at']
        ))

def insert_reservations(rows, cursor):
    """room_reservationsテーブルのデータ挿入"""
    for row in rows:
        cursor.execute("""
            INSERT INTO room_reservations (room_id, guest_id, guest_number, is_paid,
                                         reserved_at, canceled_at, start_at, end_at,
                                         total_amount, special_requests, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            row['room_id'], row['guest_id'], row['guest_number'], row['is_paid'],
            row['reserved_at'], row['canceled_at'], row['start_at'], row['end_at'],
            row['total_amount'], row['special_requests'], row['created_at'], row['updated_at']
        ))

def main():
    # データベース接続
    mysql_conn = mysql.connector.connect(**MYSQL_CONFIG)
    postgres_conn = psycopg2.connect(**POSTGRES_CONFIG)

    try:
        # テーブルの順序を考慮した移行
        tables = ['rooms', 'guests', 'room_reservations']

        for table in tables:
            migrate_table(table, mysql_conn, postgres_conn)

        logger.info("All tables migrated successfully!")

    except Exception as e:
        logger.error(f"Migration failed: {str(e)}")
        postgres_conn.rollback()
    finally:
        mysql_conn.close()
        postgres_conn.close()

if __name__ == "__main__":
    main()
```

#### 8.2.4 パフォーマンス比較

```sql
-- MySQL (元のクエリ)
EXPLAIN SELECT
    r.name,
    COUNT(rr.id) as reservation_count
FROM rooms r
LEFT JOIN room_reservations rr ON r.id = rr.room_id
WHERE rr.reserved_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY r.id, r.name
ORDER BY reservation_count DESC
LIMIT 10;

-- PostgreSQL (移行後のクエリ)
EXPLAIN (ANALYZE, BUFFERS) SELECT
    r.name,
    COUNT(rr.id) as reservation_count
FROM rooms r
LEFT JOIN room_reservations rr ON r.id = rr.room_id
WHERE rr.reserved_at >= NOW() - INTERVAL '30 days'
GROUP BY r.id, r.name
ORDER BY reservation_count DESC
LIMIT 10;
```

### 8.3 MongoDB → MySQLマイグレーション体験

#### 8.3.1 MongoDBインスタンスの準備

```bash
# ローカルでMongoDB起動（Dockerを使用）
docker run -d --name mongodb -p 27017:27017 mongo:7.0

# サンプルデータの投入
docker exec -it mongodb mongosh
```

```javascript
// MongoDB内で実行
use training_db

// JSONドキュメント形式のサンプルデータ
db.user_activities.insertMany([
    {
        userId: 1001,
        activities: [
            {
                type: "login",
                timestamp: new Date("2024-01-15T09:00:00Z"),
                metadata: { ip: "192.168.1.1", device: "mobile" }
            },
            {
                type: "search",
                timestamp: new Date("2024-01-15T09:05:00Z"),
                metadata: { query: "hotel room", filters: ["price", "location"] }
            }
        ],
        profile: {
            preferences: ["wifi", "breakfast"],
            membershipLevel: "gold"
        }
    }
])
```

#### 8.3.2 正規化変換スクリプト

```bash
vim mongo_to_mysql_migration.py
```

**mongo_to_mysql_migration.py**

```python
#!/usr/bin/env python3
import pymongo
import mysql.connector
import json
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

def normalize_user_activities(mongo_db, mysql_conn):
    """MongoDBのドキュメントをMySQLの正規化テーブルに変換"""

    cursor = mysql_conn.cursor()

    # 正規化テーブルの作成
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_profiles (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            membership_level VARCHAR(50),
            preferences JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY unique_user (user_id)
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_activities (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            activity_type VARCHAR(50) NOT NULL,
            activity_timestamp TIMESTAMP NOT NULL,
            metadata JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_user_id (user_id),
            INDEX idx_activity_type (activity_type),
            INDEX idx_timestamp (activity_timestamp)
        )
    """)

    # MongoDBからデータ取得・変換
    collection = mongo_db.user_activities

    for document in collection.find():
        user_id = document['userId']

        # プロファイル情報の挿入
        profile = document.get('profile', {})
        cursor.execute("""
            INSERT INTO user_profiles (user_id, membership_level, preferences)
            VALUES (%s, %s, %s)
            ON DUPLICATE KEY UPDATE
            membership_level = VALUES(membership_level),
            preferences = VALUES(preferences)
        """, (
            user_id,
            profile.get('membershipLevel'),
            json.dumps(profile.get('preferences', []))
        ))

        # アクティビティの挿入
        for activity in document.get('activities', []):
            cursor.execute("""
                INSERT INTO user_activities
                (user_id, activity_type, activity_timestamp, metadata)
                VALUES (%s, %s, %s, %s)
            """, (
                user_id,
                activity['type'],
                activity['timestamp'],
                json.dumps(activity.get('metadata', {}))
            ))

    mysql_conn.commit()
    logger.info("MongoDB to MySQL migration completed")

def main():
    # MongoDB接続
    mongo_client = pymongo.MongoClient("mongodb://localhost:27017/")
    mongo_db = mongo_client.training_db

    # MySQL接続
    mysql_conn = mysql.connector.connect(
        host='127.0.0.1',
        user='training_user',
        password='SecurePassword123!',
        database='training_db'
    )

    try:
        normalize_user_activities(mongo_db, mysql_conn)
    finally:
        mongo_client.close()
        mysql_conn.close()

if __name__ == "__main__":
    main()
```

### 📖 参考資料

- [MySQL 8.0 Upgrade Guide](https://dev.mysql.com/doc/refman/8.0/en/upgrading.html)
- [Cloud SQL PostgreSQL](https://cloud.google.com/sql/docs/postgres)

---

## 🔧 第9章: トラブルシューティングと運用テクニック

### 9.1 よくある問題とその対処法

#### 問題1: 突然のパフォーマンス劣化

**診断手順:**

```sql
-- 現在実行中のクエリを確認
SELECT
    id,
    user,
    host,
    db,
    command,
    time,
    state,
    LEFT(info, 100) as query_preview
FROM information_schema.processlist
WHERE command != 'Sleep'
ORDER BY time DESC;

-- ロック状況の確認
SELECT
    locked_schema,
    locked_table,
    locked_type,
    waiting_query,
    blocking_query
FROM sys.innodb_lock_waits;

-- 直近の重いクエリ
SELECT
    digest_text,
    count_star,
    ROUND(avg_timer_wait/1000000000000, 2) as avg_time_sec,
    last_seen
FROM performance_schema.events_statements_summary_by_digest
WHERE last_seen > DATE_SUB(NOW(), INTERVAL 1 HOUR)
ORDER BY avg_timer_wait DESC
LIMIT 10;
```

**対処法:**

```sql
-- 長時間実行クエリの強制終了
KILL 123456;  -- プロセスIDを指定

-- 統計情報の更新
ANALYZE TABLE table_name;

-- 必要に応じてオプティマイザヒント使用
SELECT /*+ USE_INDEX(room_reservations idx_guest_id) */
    * FROM room_reservations WHERE guest_id = 1000;
```

#### 問題2: メモリ不足によるクラッシュ

**診断:**

```sql
-- InnoDB バッファプール使用状況
SELECT
    ROUND(
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_data') /
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total') * 100, 2
    ) AS buffer_pool_data_percent;

-- 一時テーブル使用状況
SHOW GLOBAL STATUS LIKE 'Created_tmp%';
```

**対処:**

```sql
-- 設定値の確認と調整提案
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'tmp_table_size';
SHOW VARIABLES LIKE 'max_heap_table_size';
```

#### 問題3: レプリケーション遅延

```sql
-- レプリケーション状況確認
SHOW SLAVE STATUS\G

-- binlogイベント確認
SHOW BINARY LOGS;
SHOW BINLOG EVENTS IN 'mysql-bin.000001' LIMIT 10;
```

### 9.2 緊急時対応プレイブック

#### 緊急時チェックリスト

```bash
vim emergency-playbook.sh
```

**emergency-playbook.sh**

```bash
#!/bin/bash

echo "=== MySQL Emergency Response Playbook ==="
echo "Time: $(date)"

# 1. 基本ステータス確認
echo "1. MySQL Process Status"
mysql -h 127.0.0.1 -u training_user -p$MYSQL_PASSWORD -e "SHOW PROCESSLIST;" | head -20

# 2. 現在の負荷状況
echo "2. Current Load Status"
mysql -h 127.0.0.1 -u training_user -p$MYSQL_PASSWORD -e "
    SELECT
        VARIABLE_NAME,
        VARIABLE_VALUE
    FROM performance_schema.global_status
    WHERE VARIABLE_NAME IN ('Threads_running', 'Threads_connected', 'Slow_queries', 'Queries');
"

# 3. ディスク使用量確認
echo "3. Disk Usage"
mysql -h 127.0.0.1 -u training_user -p$MYSQL_PASSWORD -e "
    SELECT
        table_schema,
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.tables
    GROUP BY table_schema
    ORDER BY SUM(data_length + index_length) DESC;
"

# 4. 長時間実行クエリ
echo "4. Long Running Queries"
mysql -h 127.0.0.1 -u training_user -p$MYSQL_PASSWORD -e "
    SELECT
        id,
        user,
        host,
        time,
        LEFT(info, 200) as query
    FROM information_schema.processlist
    WHERE command != 'Sleep' AND time > 30
    ORDER BY time DESC;
"

# 5. エラーログ（最新20行）
echo "5. Recent Error Log Entries"
# Cloud SQLの場合はCloud Loggingを確認
gcloud logging read "resource.type=cloudsql_database" --limit=20 --format="table(timestamp,jsonPayload.message)"

echo "=== Emergency Check Completed ==="
```

### 9.3 運用自動化スクリプト

#### 日次メンテナンススクリプト

```bash
vim daily-maintenance.sh
```

**daily-maintenance.sh**

```bash
#!/bin/bash

LOG_FILE="/var/log/mysql-maintenance.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$DATE] $1" | tee -a $LOG_FILE
}

log "Starting daily maintenance"

# 1. バックアップ実行
log "Creating backup"
gcloud sql backups create --instance=mysql-training-instance

# 2. 統計情報更新
log "Updating table statistics"
mysql -h 127.0.0.1 -u training_user -p$MYSQL_PASSWORD training_db -e "
    ANALYZE TABLE rooms;
    ANALYZE TABLE guests;
    ANALYZE TABLE room_reservations;
    ANALYZE TABLE payments;
"

# 3. 不要な一時ファイルクリーンアップ
log "Cleaning temporary files"
mysql -h 127.0.0.1 -u training_user -p$MYSQL_PASSWORD -e "
    SET GLOBAL innodb_fast_shutdown = 1;
    FLUSH LOGS;
"

# 4. パフォーマンスレポート生成
log "Generating performance report"
mysql -h 127.0.0.1 -u training_user -p$MYSQL_PASSWORD -e "
    SELECT 'Top Slow Queries' as report_section;

    SELECT
        LEFT(digest_text, 100) as query_preview,
        count_star as exec_count,
        ROUND(avg_timer_wait/1000000000000, 2) as avg_time_sec
    FROM performance_schema.events_statements_summary_by_digest
    WHERE digest_text IS NOT NULL
    ORDER BY avg_timer_wait DESC
    LIMIT 5;

    SELECT 'Unused Indexes' as report_section;
    SELECT * FROM sys.schema_unused_indexes WHERE object_schema = 'training_db';

    SELECT 'Table Statistics' as report_section;
    SELECT * FROM sys.schema_table_statistics WHERE table_schema = 'training_db' ORDER BY total_latency DESC LIMIT 10;
" > /tmp/daily-mysql-report-$(date +%Y%m%d).txt

log "Daily maintenance completed"
```

### 9.4 容量管理とアーカイブ戦略

```sql
-- 古いデータのアーカイブ戦略例
DELIMITER //

CREATE PROCEDURE ArchiveOldReservations()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE archive_date DATE DEFAULT DATE_SUB(CURRENT_DATE, INTERVAL 2 YEAR);
    DECLARE batch_size INT DEFAULT 10000;
    DECLARE affected_rows INT;

    -- アーカイブテーブル作成（存在しない場合）
    CREATE TABLE IF NOT EXISTS room_reservations_archive LIKE room_reservations;

    REPEAT
        -- 古いデータをアーカイブテーブルに移動
        INSERT INTO room_reservations_archive
        SELECT * FROM room_reservations
        WHERE start_at < archive_date
        LIMIT batch_size;

        SET affected_rows = ROW_COUNT();

        -- 元テーブルから削除
        DELETE FROM room_reservations
        WHERE start_at < archive_date
        LIMIT batch_size;

        -- 進捗ログ
        SELECT CONCAT('Archived ', affected_rows, ' reservations') AS progress;

        -- CPU負荷を抑制
        DO SLEEP(1);

    UNTIL affected_rows = 0 END REPEAT;

    SELECT 'Archive process completed' AS result;
END //

DELIMITER ;

-- 月次実行
-- CALL ArchiveOldReservations();
```

### 📖 参考資料

- [MySQL 8.0 Troubleshooting](https://dev.mysql.com/doc/refman/8.0/en/problems.html)
- [MySQL 8.0 Performance Schema](https://dev.mysql.com/doc/refman/8.0/en/performance-schema.html)

---

## 📋 第10章: 実践課題とチェックリスト

### 10.1 実践課題

#### 課題1: パフォーマンス最適化チャレンジ

**シナリオ:** 予約システムのレスポンスが悪化している

**タスク:**

1. 問題のあるクエリを特定する
2. 適切なインデックスを設計・実装する
3. k6で負荷テストを実行し、改善を測定する

**実行手順:**

```sql
-- 1. 問題クエリの実行（意図的に遅いクエリ）
SELECT
    g.first_name,
    g.last_name,
    r.name as room_name,
    rr.reserved_at,
    rr.total_amount
FROM room_reservations rr
JOIN guests g ON rr.guest_id = g.id
JOIN rooms r ON rr.room_id = r.id
WHERE rr.start_at BETWEEN '2023-01-01' AND '2023-12-31'
AND g.guest_type = 'vip'
AND rr.is_paid = 1
ORDER BY rr.reserved_at DESC
LIMIT 50;

-- 2. EXPLAIN分析
EXPLAIN ANALYZE [上記クエリ];

-- 3. 最適化インデックス設計
-- あなたの回答：
-- ALTER TABLE ... ADD INDEX ...

-- 4. 改善後のEXPLAIN比較
EXPLAIN ANALYZE [同じクエリ];
```

#### 課題2: 障害対応シミュレーション

**シナリオ:** 突然DBの応答が止まった

**対応手順を記述してください:**

1. 初期診断で確認すべき項目
2. 問題の切り分け方法
3. 復旧手順
4. 再発防止策

#### 課題3: データベース設計レビュー

既存のテーブル設計を見直し、以下の観点で改善提案をしてください：

1. **正規化の適切性**
2. **インデックス設計**
3. **パーティショニングの必要性**
4. **JSON列の活用可能性**

### 10.2 DBRE/DBAスキルチェックリスト

#### 基礎スキル

- [ ] MySQLの基本的なCRUD操作ができる
- [ ] EXPLAINを読んで問題を特定できる
- [ ] 基本的なインデックス設計ができる
- [ ] バックアップ・リストアの手順を理解している

#### 中級スキル

- [ ] 複合インデックスの設計原則を理解している
- [ ] スロークエリログの分析ができる
- [ ] パフォーマンススキーマを活用できる
- [ ] レプリケーションの設定・管理ができる

#### 上級スキル

- [ ] クエリオプティマイザの動作を理解している
- [ ] 負荷テストの設計・実行ができる
- [ ] 容量計画とキャパシティプランニングができる
- [ ] 障害対応とパフォーマンストラブルシューティングができる

#### 運用・DevOpsスキル

- [ ] Infrastructure as Codeでのデータベース管理
- [ ] 監視・アラート設定ができる
- [ ] 自動化スクリプトの作成ができる
- [ ] セキュリティ設定とアクセス制御を理解している

### 10.3 次のステップ

#### さらなる学習のために

1. **MySQL公式認定資格**

   - MySQL Database Administrator (CMDBA)
   - MySQL Developer (CMDEV)

2. **クラウド認定**

   - Google Cloud Professional Database Engineer
   - AWS Database Specialty

3. **実践的な学習**

   - 大規模データでの実環境経験
   - マイクロサービスアーキテクチャでのDB設計
   - 分散データベースシステムの理解

4. **コミュニティ参加**
   - MySQL Meetup参加
   - 技術ブログ執筆
   - OSSへの貢献

### 📖 継続学習リソース

#### 必読書籍

- 「High Performance MySQL」
- 「Designing Data-Intensive Applications」
- 「Database Internals」

#### オンラインリソース

- [MySQL Official Documentation](https://dev.mysql.com/doc/)
- [Planet MySQL](https://planet.mysql.com/)
- [Percona Blog](https://www.percona.com/blog/)

#### 実践環境

- [MySQL Sandbox](https://github.com/datacharmer/mysql-sandbox)
- [DBFiddle](https://www.db-fiddle.com/)
- [SQLBolt](https://sqlbolt.com/)

---

## 🎯 総括

このハンズオンを通じて、以下のスキルを習得できました：

1. **理論的基礎**: B+木、インデックス、クエリオプティマイザの理解
2. **実践的技術**: EXPLAIN分析、パフォーマンスチューニング、負荷テスト
3. **インフラ管理**: Terraform、Cloud SQL、監視設定
4. **運用技術**: バックアップ・リストア、バージョンアップ、マイグレーション
5. **トラブルシューティング**: 問題特定から解決まで

これらのスキルにより、未経験からでもDBRE/DBAとして明日から実務に取り組めるレベルに到達できます。

継続的な学習と実践を通じて、さらなる専門性を高めていってください。

**Good luck with your MySQL journey! 🚀**
