# Docker Compose環境でデータベースをローカルで試す

このディレクトリには、各データベースガイドの内容をローカルで試すためのDocker Compose設定が含まれています。

## 前提条件

- Docker Desktop（またはDocker Engine + Docker Compose）がインストールされていること
- 十分なメモリ（推奨: 8GB以上）

## ディレクトリ構造

```
docker/
├── basic-theory/     # 基礎理論用（PostgreSQL + MySQL）
├── postgresql/       # PostgreSQL専用（レプリケーション付き）
├── mysql/           # MySQL専用（レプリケーション付き）
└── redis/           # Redis専用（Sentinel + クラスタ）
```

## 使い方

### 1. 基礎理論環境

基礎理論の学習用にPostgreSQLとMySQLの両方を起動します：

```bash
cd docker/basic-theory
docker-compose up -d

# PostgreSQLに接続
docker exec -it basic-theory-postgres psql -U postgres -d basic_theory_db

# MySQLに接続
docker exec -it basic-theory-mysql mysql -u root -proot_password basic_theory_db

# Web UIでアクセス
# pgAdmin: http://localhost:8081 (admin@example.com / admin_password)
# phpMyAdmin: http://localhost:8080
```

### 2. PostgreSQL環境

PostgreSQLのMVCC、レプリケーション、拡張機能を試すための環境：

```bash
cd docker/postgresql

# 設定ファイルをコピー（初回のみ）
cp config/sentinel1.conf config/sentinel2.conf
cp config/sentinel1.conf config/sentinel3.conf

# 起動
docker-compose up -d

# プライマリに接続
docker exec -it postgres-primary psql -U postgres -d training_db

# スタンバイに接続（読み取り専用）
docker exec -it postgres-standby psql -U postgres -d training_db

# pgAdmin: http://localhost:8080
# Prometheus Exporter: http://localhost:9187/metrics
```

#### PostgreSQL レプリケーション確認

```sql
-- プライマリで実行
SELECT * FROM pg_stat_replication;

-- スタンバイで実行
SELECT * FROM pg_stat_wal_receiver;
```

### 3. MySQL環境

MySQLのInnoDB、レプリケーション、パフォーマンススキーマを試すための環境：

```bash
cd docker/mysql

# 起動
docker-compose up -d

# レプリケーション設定（初回のみ）
docker exec mysql-master bash /docker-entrypoint-initdb.d/03_setup_replication.sh

# マスターに接続
docker exec -it mysql-master mysql -u root -proot_password training_db

# スレーブに接続（読み取り専用）
docker exec -it mysql-slave mysql -u root -proot_password training_db

# phpMyAdmin: http://localhost:8080
# ProxySQL Admin: mysql -h localhost -P 6032 -u admin -padmin_password
# MySQL Exporter: http://localhost:9104/metrics
```

#### MySQL レプリケーション確認

```sql
-- マスターで実行
SHOW MASTER STATUS\G

-- スレーブで実行
SHOW SLAVE STATUS\G
```

### 4. Redis環境

Redisの高可用性（Sentinel）、データ構造、Pub/Subを試すための環境：

```bash
cd docker/redis

# Sentinel設定ファイルをコピー（初回のみ）
cp config/sentinel1.conf config/sentinel2.conf
cp config/sentinel1.conf config/sentinel3.conf

# 起動
docker-compose up -d

# Redisマスターに接続
docker exec -it redis-master redis-cli -a redis_password

# Sentinel経由で接続
redis-cli -h localhost -p 26379 -a sentinel_password

# Web UI
# RedisInsight: http://localhost:8001
# Redis Commander: http://localhost:8081 (admin / admin_password)
# Redis Exporter: http://localhost:9121/metrics
```

#### Redis Sentinel フェイルオーバーテスト

```bash
# 現在のマスターを確認
redis-cli -h localhost -p 26379 -a sentinel_password sentinel masters

# マスターを停止してフェイルオーバーをテスト
docker stop redis-master

# 新しいマスターを確認
redis-cli -h localhost -p 26379 -a sentinel_password sentinel masters
```

## 環境の停止と削除

```bash
# 各ディレクトリで実行
docker-compose down

# ボリュームも含めて完全に削除
docker-compose down -v
```

## トラブルシューティング

### メモリ不足エラー

Docker Desktopの設定でメモリ割り当てを増やしてください：
- Docker Desktop → Settings → Resources → Memory: 8GB以上推奨

### ポート競合

既に使用されているポートがある場合は、docker-compose.ymlのポート設定を変更してください。

### レプリケーションが動作しない

1. コンテナを完全に削除してから再作成
2. ログを確認: `docker-compose logs [service-name]`
3. ネットワーク接続を確認: `docker network ls`

## セキュリティ注意事項

**これらの設定は学習・開発用です。本番環境では以下の対策が必要です：**

- デフォルトパスワードの変更
- ネットワークアクセスの制限
- SSL/TLS暗号化の有効化
- 適切なファイアウォール設定
- 定期的なセキュリティアップデート