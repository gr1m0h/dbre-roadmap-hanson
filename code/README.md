# コードサンプル一覧

このディレクトリには、DBRE学習ロードマップで使用するコードサンプルが格納されています。

## 📁 ディレクトリ構成

```
code/
├── postgresql/          # PostgreSQL関連
│   ├── setup/          # 環境構築
│   ├── examples/       # 実装例
│   ├── monitoring/     # 監視・分析
│   ├── migrations/     # マイグレーション
│   └── loadtest/       # 負荷テスト
├── mysql/              # MySQL関連
│   ├── examples/       # 実装例
│   └── migrations/     # マイグレーション
├── redis/              # Redis関連
│   ├── setup/          # 環境構築
│   ├── examples/       # 実装例
│   └── loadtest/       # 負荷テスト
└── mongodb/            # MongoDB関連
    ├── setup/          # 環境構築
    ├── examples/       # 実装例
    └── migrations/     # マイグレーション
```

## 🐘 PostgreSQL

### 環境構築
- [terraform_rds.hcl](postgresql/setup/terraform_rds.hcl) - Terraform RDS設定

### 実装例
- [schema_design.sql](postgresql/examples/schema_design.sql) - テーブル設計例（JSONB、パーティション等）
- [index_examples.sql](postgresql/examples/index_examples.sql) - インデックス戦略
- [mvcc_demo.sql](postgresql/examples/mvcc_demo.sql) - MVCC動作確認

### 監視・分析
- [log_analyzer.py](postgresql/monitoring/log_analyzer.py) - ログ分析ツール

### マイグレーション
- [mysql_to_postgresql.py](postgresql/migrations/mysql_to_postgresql.py) - MySQL → PostgreSQL
- [mongodb_to_postgresql.py](postgresql/migrations/mongodb_to_postgresql.py) - MongoDB → PostgreSQL

## 🐬 MySQL

### 実装例
- MySQL差分学習用のコード例

## ⚡ Redis

### 実装例
- [session_manager.py](redis/examples/session_manager.py) - セッション管理システム
- [sentinel_manager.py](redis/examples/sentinel_manager.py) - Sentinel管理システム

## 🍃 MongoDB

### 実装例
- [document_design.js](mongodb/examples/document_design.js) - ドキュメント設計パターン
- [geospatial_index.js](mongodb/examples/geospatial_index.js) - 地理空間インデックス

## 🚀 使用方法

各コードファイルの冒頭に使用方法が記載されています。

### SQL
```bash
psql -f code/postgresql/examples/schema_design.sql
```

### Python
```bash
python code/postgresql/monitoring/log_analyzer.py /var/log/postgresql.log
```

### JavaScript
```bash
mongosh < code/mongodb/examples/document_design.js
```

## 📝 ライセンス

教育目的での使用を想定しています。
