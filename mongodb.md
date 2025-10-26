# DB実践編：MongoDB

## 概要

このドキュメントは、MongoDBの本格的な運用・管理スキルを体系的に身につけるためのハンズオンガイドです。**「なぜドキュメント指向DBが必要なのか？」「どのようにスキーマレスを設計すべきか？」**といった実際の運用で直面する課題を、理論的背景とともに実践的に解決する能力を養います。

> **前提知識**: [PostgreSQL版ハンズオン](./postgresql.md)、[Redis版ハンズオン](./redis.md)で学習したRDBMS・NoSQLの基本概念は理解済みとします。

**なぜMongoDB運用スキルが重要なのか？**

- **ドキュメント指向**: JSON形式の柔軟なデータモデリング
- **スキーマレス**: 迅速な開発とアジャイルな変更対応
- **水平スケーリング**: シャーディングによる大規模データ対応
- **高速な読み書き**: インメモリ処理とインデックス最適化

**学習目標:**

- MongoDB 6.0+ のドキュメント指向アーキテクチャの理解
- スキーマ設計パターンとデータモデリング手法
- インデックス戦略とクエリ最適化
- レプリカセットによる高可用性構成
- シャーディングによる水平スケーリング
- アグリゲーションパイプラインによるデータ分析
- RDBMS からの移行戦略

**MongoDB特有の学習内容:**

- ドキュメント指向データモデル
- BSON (Binary JSON) 形式
- WiredTiger ストレージエンジン
- レプリカセット構成
- シャーディングアーキテクチャ
- アグリゲーションパイプライン
- Change Streams（リアルタイムデータ変更通知）

## 🛠 必要な環境・ツール

> **PostgreSQL版と共通**: 基本的な環境構築（Terraform、k6、GCP等）は [PostgreSQL版](./postgresql.md) を参照してください。

### MongoDB特有のツール

```bash
# MongoDB Shell のインストール
brew install mongosh

# MongoDB Compass のインストール（GUI管理ツール）
brew install --cask mongodb-compass

# MongoDB用GCP設定
gcloud services enable servicenetworking.googleapis.com
```

---

## 📚 第1章: MongoDB基礎とドキュメント指向アーキテクチャ

### 1.1 なぜドキュメント指向なのか？

**「なぜRDBMSではなくドキュメントDBを選ぶのか？」**という疑問に答えるため、データモデリングの根本的な違いを理解しましょう。

#### RDBMSとの比較

```javascript
// RDBMS (PostgreSQL/MySQL)の場合
// テーブル分割が必要（正規化）

-- users テーブル
CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(255)
);

-- addresses テーブル
CREATE TABLE addresses (
    id INT PRIMARY KEY,
    user_id INT REFERENCES users(id),
    street VARCHAR(255),
    city VARCHAR(100)
);

-- orders テーブル
CREATE TABLE orders (
    id INT PRIMARY KEY,
    user_id INT REFERENCES users(id),
    total_amount DECIMAL(10,2)
);

// クエリ: ユーザーと住所と注文を取得（JOIN必須）
SELECT u.*, a.*, o.*
FROM users u
LEFT JOIN addresses a ON u.id = a.user_id
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.id = 1001;


// MongoDB の場合
// 1つのドキュメントに集約可能（非正規化）

db.users.insertOne({
    _id: 1001,
    name: "John Doe",
    email: "john@example.com",
    addresses: [
        {
            type: "home",
            street: "123 Main St",
            city: "Tokyo"
        },
        {
            type: "office",
            street: "456 Business Ave",
            city: "Osaka"
        }
    ],
    orders: [
        {
            order_id: "ORD-2024-001",
            total_amount: 15000,
            items: [
                { product: "Laptop", quantity: 1, price: 12000 },
                { product: "Mouse", quantity: 2, price: 1500 }
            ],
            ordered_at: ISODate("2024-01-15T10:30:00Z")
        }
    ],
    created_at: ISODate("2023-06-01T00:00:00Z")
});

// クエリ: ユーザー情報を1回のクエリで取得（JOIN不要）
db.users.findOne({ _id: 1001 });
```

**ドキュメント指向の利点:**

1. **JOIN不要**: 関連データを1つのドキュメントに集約
2. **柔軟なスキーマ**: フィールド追加が容易
3. **オブジェクトマッピング**: アプリケーションコードとの親和性
4. **高速読み取り**: 1回のクエリで完結

**注意点:**

- データの重複が発生しやすい
- 更新の複雑さ（埋め込みドキュメントの更新）
- トランザクション範囲の制限（MongoDB 4.0+ で改善）

### 1.2 BSONフォーマットとデータ型

#### BSON vs JSON

```javascript
// JSON: テキスト形式
{
    "name": "John",
    "age": 30,
    "created_at": "2024-01-15T10:30:00Z"
}

// BSON: バイナリ形式（MongoDB内部）
// - 高速なパース
// - 追加のデータ型サポート
// - サイズ情報の埋め込み

// BSON特有のデータ型
db.examples.insertOne({
    // ObjectId: 12バイトの一意識別子
    _id: ObjectId("507f1f77bcf86cd799439011"),
    
    // Date: UTCタイムスタンプ
    created_at: new Date(),
    
    // Binary Data: バイナリデータ
    avatar: BinData(0, "iVBORw0KGgo..."),
    
    // Decimal128: 高精度10進数
    price: NumberDecimal("19.99"),
    
    // Int32, Int64
    count: NumberInt(100),
    big_number: NumberLong("9223372036854775807"),
    
    // Regular Expression
    pattern: /^test/i,
    
    // Array
    tags: ["mongodb", "nosql", "database"],
    
    // Embedded Document
    address: {
        street: "123 Main St",
        city: "Tokyo"
    }
});
```

### 1.3 コレクション設計パターン

📄 [document_design.js](code/mongodb/examples/document_design.js) - 埋め込み、参照、バケットパターンの実装例

#### パターン1: 埋め込み (Embedding)

**ユースケース:** 1対少数の関係、常に一緒に取得するデータ

**メリット:**
- 1回のクエリで取得
- アトミックな更新
- パフォーマンスが高い

**デメリット:**
- ドキュメントサイズ制限（16MB）
- コメントが多い場合は非効率

#### パターン2: 参照 (Referencing)

**ユースケース:** 1対多数の関係、独立して更新するデータ

**メリット:**
- ドキュメントサイズ制限回避
- 独立した更新
- 柔軟なクエリ

**デメリット:**
- 複数クエリまたは$lookup必要
- パフォーマンスはやや低下

#### パターン3: バケットパターン (Bucketing)

**ユースケース:** 時系列データ、IoTセンサーデータ

```javascript
// ユースケース: 時系列データ、IoTセンサーデータ

// 1時間ごとにバケット化
db.sensor_data.insertOne({
    sensor_id: "sensor_001",
    bucket_time: ISODate("2024-01-15T10:00:00Z"),  // 時間単位
    measurements: [
        { time: ISODate("2024-01-15T10:00:15Z"), temp: 22.5, humidity: 45 },
        { time: ISODate("2024-01-15T10:01:15Z"), temp: 22.6, humidity: 46 },
        { time: ISODate("2024-01-15T10:02:15Z"), temp: 22.4, humidity: 45 },
        // ... 1時間分（最大240件）
    ],
    count: 240
});

// メリット:
// - ドキュメント数削減
// - 効率的なストレージ
// - 高速なクエリ

// クエリ例
db.sensor_data.find({
    sensor_id: "sensor_001",
    bucket_time: {
        $gte: ISODate("2024-01-15T10:00:00Z"),
        $lt: ISODate("2024-01-15T11:00:00Z")
    }
});
```

---

## 🗂 第2章: MongoDB インデックス戦略

### 2.1 インデックスの種類

#### 1. 単一フィールドインデックス

```javascript
// 基本的なインデックス作成
db.users.createIndex({ email: 1 });  // 昇順
db.users.createIndex({ created_at: -1 });  // 降順

// インデックス使用確認
db.users.find({ email: "john@example.com" }).explain("executionStats");
```

#### 2. 複合インデックス

```javascript
// 複数フィールドの複合インデックス
db.orders.createIndex({ user_id: 1, created_at: -1 });

// 効果的なクエリ
db.orders.find({ user_id: 1001 }).sort({ created_at: -1 });

// インデックスプレフィックス活用
// { user_id: 1, created_at: -1 } は以下のクエリにも使用可能:
db.orders.find({ user_id: 1001 });  // ✅ インデックス使用
db.orders.find({ created_at: { $gt: new Date() } });  // ❌ インデックス不使用（プレフィックスでない）
```

#### 3. マルチキーインデックス（配列）

```javascript
// 配列フィールドのインデックス
db.articles.createIndex({ tags: 1 });

// 配列要素での検索が高速化
db.articles.find({ tags: "mongodb" });
db.articles.find({ tags: { $in: ["mongodb", "nosql"] } });

// 複合マルチキーインデックスの制限
// ❌ 複数の配列フィールドに複合インデックスは作成不可
db.articles.createIndex({ tags: 1, categories: 1 });  // エラー
```

#### 4. テキストインデックス（全文検索）

```javascript
// 全文検索インデックス
db.articles.createIndex({
    title: "text",
    content: "text"
}, {
    weights: {
        title: 10,  // タイトルの重み付け
        content: 1
    },
    default_language: "english"
});

// 全文検索クエリ
db.articles.find({
    $text: {
        $search: "mongodb database tutorial"
    }
}).sort({
    score: { $meta: "textScore" }  // 関連度スコアでソート
});

// 日本語対応（要設定）
db.articles_ja.createIndex({
    title: "text",
    content: "text"
}, {
    default_language: "japanese"
});
```

#### 5. 地理空間インデックス

📄 [geospatial_index.js](code/mongodb/examples/geospatial_index.js) - 2dsphere インデックス、近傍検索、エリア内検索の実装例

#### 6. ハッシュドインデックス

```javascript
// シャーディング用のハッシュドインデックス
db.users.createIndex({ _id: "hashed" });

// 均等な分散を実現
// 範囲クエリには使用不可
```

### 2.2 インデックス最適化

#### Covered Query（カバリングクエリ）

```javascript
// インデックスのみで完結するクエリ（ディスクI/O不要）

// インデックス作成
db.users.createIndex({ email: 1, name: 1 });

// カバリングクエリ
db.users.find(
    { email: "john@example.com" },
    { _id: 0, email: 1, name: 1 }  // _id を除外
).explain("executionStats");

// totalDocsExamined: 0 ← ドキュメント読み取りなし（高速）
```

#### インデックスの圧縮（Prefix Compression）

```javascript
// WiredTigerストレージエンジンでは自動圧縮
// 設定確認
db.collection.stats().wiredTiger.creationString;
```

---

## 📊 第3章: アグリゲーションパイプライン

### 3.1 アグリゲーションの基本

```javascript
// パイプラインステージの連鎖
db.orders.aggregate([
    // ステージ1: フィルタリング
    {
        $match: {
            created_at: {
                $gte: ISODate("2024-01-01"),
                $lt: ISODate("2024-02-01")
            }
        }
    },
    
    // ステージ2: グループ化と集計
    {
        $group: {
            _id: "$user_id",
            total_orders: { $sum: 1 },
            total_amount: { $sum: "$total_amount" },
            avg_amount: { $avg: "$total_amount" }
        }
    },
    
    // ステージ3: ソート
    {
        $sort: { total_amount: -1 }
    },
    
    // ステージ4: 制限
    {
        $limit: 10
    }
]);
```

### 3.2 高度なアグリゲーション

#### $lookup（JOIN相当）

```javascript
db.orders.aggregate([
    {
        $lookup: {
            from: "users",
            localField: "user_id",
            foreignField: "_id",
            as: "user_info"
        }
    },
    {
        $unwind: "$user_info"  // 配列を展開
    },
    {
        $project: {
            order_id: 1,
            total_amount: 1,
            user_name: "$user_info.name",
            user_email: "$user_info.email"
        }
    }
]);
```

#### $facet（複数集計の並列実行）

```javascript
db.products.aggregate([
    {
        $facet: {
            // 集計1: カテゴリ別集計
            by_category: [
                {
                    $group: {
                        _id: "$category",
                        count: { $sum: 1 },
                        avg_price: { $avg: "$price" }
                    }
                }
            ],
            
            // 集計2: 価格帯別集計
            by_price_range: [
                {
                    $bucket: {
                        groupBy: "$price",
                        boundaries: [0, 1000, 5000, 10000, 50000],
                        default: "Other",
                        output: {
                            count: { $sum: 1 },
                            products: { $push: "$name" }
                        }
                    }
                }
            ],
            
            // 集計3: 全体統計
            overall_stats: [
                {
                    $group: {
                        _id: null,
                        total: { $sum: 1 },
                        avg_price: { $avg: "$price" },
                        max_price: { $max: "$price" }
                    }
                }
            ]
        }
    }
]);
```

---

## 🔄 第4章: レプリカセットと高可用性

### 4.1 レプリカセットアーキテクチャ

```javascript
// レプリカセット構成（3ノード推奨）
/*
Primary (プライマリ): 読み書き可能
   ↓ レプリケーション
Secondary (セカンダリ): 読み取り可能（オプション）
   ↓ レプリケーション
Secondary (セカンダリ): 読み取り可能（オプション）

障害発生時:
Primary が落ちると → 自動フェイルオーバー
Secondary の1つが Primary に昇格
*/

// レプリカセット設定確認
rs.status();
rs.conf();

// セカンダリからの読み取り許可
db.getMongo().setReadPref("secondaryPreferred");

// 読み取り優先度設定
db.collection.find().readPref("secondary");  // セカンダリから読む
db.collection.find().readPref("primary");    // プライマリから読む
db.collection.find().readPref("primaryPreferred");  // プライマリ優先
```

### 4.2 Write Concern と Read Concern

```javascript
// Write Concern: 書き込み確認レベル

// w: 1（デフォルト）- プライマリのみ確認
db.orders.insertOne(
    { user_id: 1001, total: 5000 },
    { writeConcern: { w: 1 } }
);

// w: "majority" - 過半数のノードに複製後に確認（推奨）
db.orders.insertOne(
    { user_id: 1001, total: 5000 },
    { writeConcern: { w: "majority", wtimeout: 5000 } }
);

// w: 3 - 3ノードに複製後に確認
db.orders.insertOne(
    { user_id: 1001, total: 5000 },
    { writeConcern: { w: 3 } }
);


// Read Concern: 読み取り一貫性レベル

// local: ローカルデータ（最速だが複製未完了の可能性）
db.orders.find().readConcern("local");

// majority: 過半数に複製済みのデータのみ
db.orders.find().readConcern("majority");

// linearizable: 線形化可能（最も厳密、性能低下）
db.orders.find().readConcern("linearizable");
```

---

## 🗄 第5章: シャーディング（水平スケーリング）

### 5.1 シャーディングアーキテクチャ

```javascript
/*
シャーディング構成:

mongos (ルーター) ← アプリケーションはここに接続
   ↓
Config Servers (メタデータ管理)
   ↓
Shard 1 (レプリカセット) | Shard 2 (レプリカセット) | Shard 3 (レプリカセット)
   データ範囲 A-M      |    データ範囲 N-T      |    データ範囲 U-Z
*/

// シャーディング有効化
sh.enableSharding("mydb");

// シャードキー選択（重要！）
sh.shardCollection("mydb.users", { user_id: 1 });

// シャード状態確認
sh.status();
```

### 5.2 シャードキー設計

```javascript
// パターン1: ハッシュドシャードキー
// メリット: 均等な分散
// デメリット: 範囲クエリに弱い
sh.shard Collection("mydb.users", { _id: "hashed" });

// パターン2: 範囲ベースシャードキー
// メリット: 範囲クエリが効率的
// デメリット: ホットスポットの可能性
sh.shardCollection("mydb.orders", { created_at: 1 });

// パターン3: 複合シャードキー
// メリット: 柔軟な分散とクエリ効率
sh.shardCollection("mydb.products", {
    category: 1,
    product_id: 1
});
```

---

## 📈 第6章: パフォーマンスチューニング

### 6.1 クエリ最適化

```javascript
// explain() による実行計画分析
db.users.find({ email: "test@example.com" }).explain("executionStats");

// 重要な指標:
// - totalDocsExamined: スキャンしたドキュメント数
// - totalKeysExamined: スキャンしたインデックスキー数
// - executionTimeMillis: 実行時間
// - stage: 実行ステージ（COLLSCAN, IXSCAN等）

// 理想: totalDocsExamined ≒ nReturned（不要なスキャンなし）
```

### 6.2 監視とプロファイリング

```javascript
// プロファイラ有効化
db.setProfilingLevel(2);  // 0: オフ, 1: スロークエリのみ, 2: 全クエリ

// スロークエリ閾値設定
db.setProfilingLevel(1, { slowms: 100 });  // 100ms以上

// プロファイル結果確認
db.system.profile.find().limit(10).sort({ ts: -1 }).pretty();

// 現在の操作確認
db.currentOp();

// 長時間実行中のクエリ特定
db.currentOp({ "active": true, "secs_running": { $gt: 5 } });
```

---

## 🔄 第7章: RDBMS → MongoDB マイグレーション

### 7.1 スキーマ設計の変換

```javascript
// PostgreSQL スキーマ
/*
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE,
    name VARCHAR(100)
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    total_amount DECIMAL(10,2),
    created_at TIMESTAMP
);
*/

// MongoDB スキーマパターン1: 埋め込み
db.users.insertOne({
    _id: ObjectId(),
    email: "user@example.com",
    name: "John Doe",
    orders: [  // 埋め込み
        {
            order_id: "ORD001",
            total_amount: 15000,
            created_at: new Date()
        }
    ]
});

// MongoDB スキーマパターン2: 参照
db.users.insertOne({
    _id: ObjectId("user001"),
    email: "user@example.com",
    name: "John Doe"
});

db.orders.insertOne({
    _id: ObjectId(),
    user_id: ObjectId("user001"),  // 参照
    total_amount: 15000,
    created_at: new Date()
});
```

### 7.2 マイグレーションスクリプト

```python
#!/usr/bin/env python3
# postgresql_to_mongodb_migration.py

import psycopg2
import pymongo
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# PostgreSQL接続
pg_conn = psycopg2.connect(
    host='localhost',
    database='source_db',
    user='postgres',
    password='password'
)

# MongoDB接続
mongo_client = pymongo.MongoClient('mongodb://localhost:27017/')
mongo_db = mongo_client['target_db']

def migrate_users():
    """ユーザーデータ移行"""
    pg_cursor = pg_conn.cursor()
    pg_cursor.execute("SELECT id, email, name, created_at FROM users")
    
    users_batch = []
    for row in pg_cursor:
        user_doc = {
            '_id': str(row[0]),  # PostgreSQL ID を文字列として使用
            'email': row[1],
            'name': row[2],
            'created_at': row[3],
            'migrated_at': datetime.utcnow()
        }
        users_batch.append(user_doc)
        
        if len(users_batch) >= 1000:
            mongo_db.users.insert_many(users_batch)
            users_batch = []
            logger.info(f"Migrated {pg_cursor.rowcount} users")
    
    if users_batch:
        mongo_db.users.insert_many(users_batch)
    
    logger.info("User migration completed")

def migrate_orders_embedded():
    """注文データ移行（埋め込みパターン）"""
    pg_cursor = pg_conn.cursor()
    pg_cursor.execute("""
        SELECT user_id, id, total_amount, created_at
        FROM orders
        ORDER BY user_id
    """)
    
    current_user_id = None
    orders = []
    
    for row in pg_cursor:
        user_id = str(row[0])
        
        if user_id != current_user_id:
            if current_user_id and orders:
                # 前のユーザーの注文を埋め込み
                mongo_db.users.update_one(
                    {'_id': current_user_id},
                    {'$set': {'orders': orders}}
                )
            current_user_id = user_id
            orders = []
        
        order = {
            'order_id': str(row[1]),
            'total_amount': float(row[2]),
            'created_at': row[3]
        }
        orders.append(order)
    
    # 最後のユーザー処理
    if current_user_id and orders:
        mongo_db.users.update_one(
            {'_id': current_user_id},
            {'$set': {'orders': orders}}
        )
    
    logger.info("Order migration (embedded) completed")

if __name__ == "__main__":
    migrate_users()
    migrate_orders_embedded()
    
    pg_conn.close()
    mongo_client.close()
```

---

## 🎯 総括

本MongoDBハンズオンでは、RDBMS とは異なる以下の技術を習得しました：

### 🔑 核心技術

1. **ドキュメント指向**: JSON/BSON による柔軟なデータモデリング
2. **スキーマレス**: 迅速な開発とアジャイル対応
3. **シャーディング**: 水平スケーリングによる大規模化対応
4. **アグリゲーションパイプライン**: 強力なデータ分析機能
5. **レプリカセット**: 高可用性と自動フェイルオーバー

### 💡 実践スキル

- ドキュメント設計パターンの使い分け
- インデックス戦略によるパフォーマンス最適化
- アグリゲーションによる複雑な分析
- シャーディングによるスケールアウト
- RDBMS からのマイグレーション

### 🚀 次のステップ

MongoDB は単なるドキュメント DB を超えて、多様なユースケースに対応できます：
- **リアルタイムアプリ**: Change Streams
- **モバイルバックエンド**: Realm
- **検索エンジン**: Atlas Search
- **時系列データ**: Time Series Collections

**継続学習により、真の MongoDB エキスパートを目指してください！**

---

> **次のステップ**: NoSQL 学習完了後は [学習ロードマップ](./README.md) Phase 4（統合運用）へ
