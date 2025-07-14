# DB実践編：Redis

## 概要

このドキュメントは、Redisの本格的な運用・管理スキルを体系的に身につけるためのハンズオンガイドです。**「なぜインメモリデータストアが高速なのか？」「どのようにキャッシュ戦略を設計すべきか？」**といった実際の運用で直面する課題を、理論的背景とともに実践的に解決する能力を養います。

> **前提知識**: [MySQL版ハンズオン](./mysql.md)、[PostgreSQL版ハンズオン](./postgresql.md)で学習した基本的なデータベース概念、Terraform、k6の使い方は理解済みとします。

**なぜRedis運用スキルが重要なのか？**

- **高速データアクセス**: インメモリアーキテクチャによる超高速レスポンス
- **多様なデータ構造**: 用途に応じた最適なデータ型の選択
- **リアルタイム処理**: セッション管理・キャッシュ・メッセージキューの実現
- **スケーラビリティ**: 分散アーキテクチャによる水平スケーリング

**学習目標:**

- Redis 7.0のインメモリアーキテクチャの理解と実践的運用・管理スキル
- 多様なデータ構造の効果的な使い分けと最適化手法
- 高可用性・クラスタリング構成の設計と運用
- パフォーマンスチューニングとメモリ最適化
- セッション管理・キャッシュ・リアルタイム分析の実装
- 監視とトラブルシューティングの体系的アプローチ

**Redis特有の学習内容:**

- インメモリデータストアアーキテクチャ
- 多様なデータ構造（String, Hash, List, Set, Sorted Set, Stream, JSON等）
- 永続化戦略（RDB、AOF）
- 高可用性・クラスタリング
- キャッシュ戦略・セッション管理
- リアルタイム分析・メッセージキュー
- Lua スクリプティング

## 🛠 必要な環境・ツール

### 必須ツール

- **Google Cloud Platform アカウント**（無料クレジット利用可）
- **Terraform** >= 1.0
- **Git**
- **k6** (負荷テストツール)
- **Vim** (エディタ)
- **Redis Client** (redis-cli)

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

# Redis Client のインストール
brew install redis
```

### Google Cloud プロジェクトの準備

```bash
# プロジェクトの作成
gcloud projects create redis-dbre-training-[YOUR-ID]
gcloud config set project redis-dbre-training-[YOUR-ID]

# 必要なAPIの有効化
gcloud services enable compute.googleapis.com
gcloud services enable redis.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable logging.googleapis.com
```

## 🏗 環境構築

### 基本環境準備

> **MySQL/PostgreSQL版と共通**: Google Cloud Platform アカウント、Terraform、Git、k6、Vimの準備は[MySQL版 第2章](./mysql.md#第2章-terraformを使ったmysql環境構築)を参照

### Redis特化Terraform設定

**main.tf**（Redis特化部分）

```hcl
# Redis Memorystore インスタンス
resource "google_redis_instance" "redis_cache" {
  name           = "redis-training-cache"
  memory_size_gb = 4
  region         = var.region

  # Redis version
  redis_version = "REDIS_7_0"

  # 高可用性設定
  tier = "STANDARD_HA"  # 高可用性モード

  # ネットワーク設定
  authorized_network = google_compute_network.vpc_network.id

  # Redis設定
  redis_configs = {
    maxmemory-policy           = "allkeys-lru"
    notify-keyspace-events     = "Ex"
    timeout                    = "3600"
    tcp-keepalive             = "60"

    # 永続化設定
    save                      = "900 1 300 10 60 10000"

    # パフォーマンス設定
    hash-max-ziplist-entries  = "512"
    hash-max-ziplist-value    = "64"
    list-max-ziplist-size     = "-2"
    set-max-intset-entries    = "512"
    zset-max-ziplist-entries  = "128"
    zset-max-ziplist-value    = "64"
  }

  # メンテナンス設定
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 3
        minutes = 0
      }
    }
  }

  labels = {
    environment = "training"
    purpose     = "cache"
  }
}

# Redis クラスタ（シャーディング用）
resource "google_redis_cluster" "redis_cluster" {
  name           = "redis-training-cluster"
  shard_count    = 3
  replica_count  = 1
  region         = var.region

  node_type      = "redis-highmem-medium"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  # ネットワーク設定
  authorization_mode = "AUTH_DISABLED"  # 学習用のため
  transit_encryption_mode = "TRANSIT_ENCRYPTION_MODE_DISABLED"

  # 削除保護（本番では有効化）
  deletion_protection = false
}

# Pub/Sub用Redis
resource "google_redis_instance" "redis_pubsub" {
  name           = "redis-training-pubsub"
  memory_size_gb = 2
  region         = var.region
  redis_version  = "REDIS_7_0"
  tier           = "BASIC"

  authorized_network = google_compute_network.vpc_network.id

  redis_configs = {
    notify-keyspace-events = "AKE"  # Pub/Sub用設定
    timeout               = "0"      # 永続接続
  }
}
```

**outputs.tf**（Redis特化部分）

```hcl
output "redis_cache_host" {
  description = "Redis cache instance host"
  value       = google_redis_instance.redis_cache.host
}

output "redis_cache_port" {
  description = "Redis cache instance port"
  value       = google_redis_instance.redis_cache.port
}

output "redis_cluster_discovery_endpoints" {
  description = "Redis cluster discovery endpoints"
  value       = google_redis_cluster.redis_cluster.discovery_endpoints
}

output "redis_pubsub_host" {
  description = "Redis pub/sub instance host"
  value       = google_redis_instance.redis_pubsub.host
}
```

**startup-script.sh**（Redis特化部分）

```bash
#!/bin/bash

# 基本システム更新（共通）
apt-get update && apt-get upgrade -y

# Redis Tools インストール
apt-get install -y redis-tools

# redis-cli 強化版
wget https://github.com/lework/redismanager/releases/download/v1.0.0/redismanager-linux-amd64
chmod +x redismanager-linux-amd64
mv redismanager-linux-amd64 /usr/local/bin/redismanager

# Python Redis client
apt-get install -y python3-pip
pip3 install redis redis-py-cluster hiredis

# Node.js Redis client（アプリケーション開発用）
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt-get install -y nodejs
npm install -g redis-commander  # Web UI

# Redis監視ツール
pip3 install redis-memory-analyzer

# k6（MySQL版と同じ）
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
apt-get update && apt-get install k6

# 監視ツール
apt-get install -y htop iotop sysstat nethogs

echo "Redis setup completed" >> /var/log/startup-script.log
```

---

## 📚 第1章: Redis基礎とアーキテクチャ

### 1.1 なぜRedisが高速なのか？

Redisの高速性を理解するためには、従来のディスクベースデータベースとインメモリデータストアの根本的な違いを知る必要があります。**「なぜRedisはこんなに速いのか？」**という疑問に答えるため、メモリアクセスの仕組みを詳しく見てみましょう。

#### インメモリデータストアの概念

```bash
# Redis接続
redis-cli -h $REDIS_HOST -p $REDIS_PORT

# 基本的な操作
redis> SET user:1001:name "John Doe"
redis> GET user:1001:name
redis> EXISTS user:1001:name
redis> DEL user:1001:name

# TTL（Time To Live）設定
redis> SET session:abc123 "user_data" EX 3600  # 1時間で自動削除
redis> TTL session:abc123
redis> EXPIRE user:1001:name 600  # 10分後に削除
```

#### メモリ管理とデータ永続化

**メモリ使用量確認:**

```bash
redis> INFO memory
redis> MEMORY USAGE user:1001:name
redis> MEMORY STATS
```

**永続化機能:**

```bash
# RDB（Redis Database）- スナップショット
redis> SAVE        # 同期保存
redis> BGSAVE      # バックグラウンド保存
redis> LASTSAVE    # 最終保存時刻

# AOF（Append Only File）- 追記ログ
redis> BGREWRITEAOF  # AOF再構築
```

### 1.2 Redisデータ構造とユースケース

#### 1. String（文字列）- 最も基本的なデータ型

```bash
# 基本操作
redis> SET counter 0
redis> INCR counter        # アトミックな増加
redis> INCRBY counter 5    # 指定値だけ増加
redis> DECR counter        # アトミックな減少

# ビット操作
redis> SETBIT user:active:20241215 1001 1  # ユーザー1001がアクティブ
redis> GETBIT user:active:20241215 1001
redis> BITCOUNT user:active:20241215       # アクティブユーザー数

# 用途例：カウンター、フラグ、キャッシュ、セッション
```

#### 2. Hash（ハッシュ）- オブジェクト表現

```bash
# ユーザープロファイル管理
redis> HSET user:1001 name "John Doe" email "john@example.com" age 30
redis> HGET user:1001 name
redis> HGETALL user:1001
redis> HINCRBY user:1001 login_count 1

# バルク操作
redis> HMSET user:1002 name "Jane Smith" email "jane@example.com" age 25
redis> HMGET user:1002 name email

# 用途例：ユーザープロファイル、設定情報、オブジェクトキャッシュ
```

#### 3. List（リスト）- 順序付きコレクション

```bash
# キュー実装（FIFO）
redis> LPUSH task_queue "task1" "task2" "task3"
redis> RPOP task_queue

# スタック実装（LIFO）
redis> LPUSH recent_activities "login" "purchase" "logout"
redis> LPOP recent_activities

# リアルタイムログ
redis> LPUSH logs:error "Error: Connection timeout"
redis> LTRIM logs:error 0 999  # 最新1000件のみ保持

# 用途例：メッセージキュー、最近のアクティビティ、ログ、タイムライン
```

#### 4. Set（セット）- 重複なしコレクション

```bash
# タグ管理
redis> SADD article:123:tags "redis" "database" "caching"
redis> SMEMBERS article:123:tags
redis> SISMEMBER article:123:tags "redis"

# セット演算
redis> SADD favorites:user1 "item1" "item2" "item3"
redis> SADD favorites:user2 "item2" "item3" "item4"
redis> SINTER favorites:user1 favorites:user2  # 共通の好み
redis> SUNION favorites:user1 favorites:user2  # すべての好み
redis> SDIFF favorites:user1 favorites:user2   # user1だけの好み

# 用途例：タグ、カテゴリ、権限、重複排除、推薦システム
```

#### 5. Sorted Set（ソート済みセット）- スコア付きコレクション

```bash
# リーダーボード
redis> ZADD leaderboard 1000 "player1" 1500 "player2" 1200 "player3"
redis> ZREVRANGE leaderboard 0 9  # TOP10取得
redis> ZRANK leaderboard "player1"  # ランク取得
redis> ZINCRBY leaderboard 100 "player1"  # スコア増加

# 時系列データ
redis> ZADD events 1640995200 "event1" 1640995260 "event2"
redis> ZRANGEBYSCORE events 1640995200 1640995300  # 時間範囲検索

# 用途例：ランキング、時系列データ、優先度付きキュー、レート制限
```

#### 6. Stream（ストリーム）- Redis 5.0以降

```bash
# イベントストリーム
redis> XADD events * user_id 1001 action "login" timestamp 1640995200
redis> XADD events * user_id 1002 action "purchase" item_id 5432

# ストリーム読み取り
redis> XREAD STREAMS events 0
redis> XRANGE events - +  # 全イベント取得

# コンシューマーグループ
redis> XGROUP CREATE events processing $ MKSTREAM
redis> XREADGROUP GROUP processing consumer1 STREAMS events >

# 用途例：イベントログ、メッセージング、リアルタイム分析
```

### 📖 参考資料

- [Redis Data Types](https://redis.io/docs/data-types/)
- [Redis Commands](https://redis.io/commands/)
- [Redis Persistence](https://redis.io/docs/management/persistence/)

---

## 🏗 第2章: 実践的Redis応用システム

### 2.1 セッション管理システム

```python
#!/usr/bin/env python3
# session_manager.py

import redis
import json
import uuid
from datetime import datetime, timedelta
import hashlib

class RedisSessionManager:
    def __init__(self, redis_host, redis_port, default_ttl=3600):
        self.redis_client = redis.Redis(
            host=redis_host,
            port=redis_port,
            decode_responses=True
        )
        self.default_ttl = default_ttl

    def create_session(self, user_id, user_data=None):
        """セッション作成"""
        session_id = str(uuid.uuid4())
        session_key = f"session:{session_id}"

        session_data = {
            'user_id': user_id,
            'created_at': datetime.now().isoformat(),
            'last_accessed': datetime.now().isoformat(),
            'data': user_data or {}
        }

        # セッションデータ保存（Hash使用）
        self.redis_client.hset(session_key, mapping=session_data)
        self.redis_client.expire(session_key, self.default_ttl)

        # ユーザーのアクティブセッション管理（Set使用）
        user_sessions_key = f"user_sessions:{user_id}"
        self.redis_client.sadd(user_sessions_key, session_id)
        self.redis_client.expire(user_sessions_key, self.default_ttl)

        return session_id

    def get_session(self, session_id):
        """セッション取得"""
        session_key = f"session:{session_id}"
        session_data = self.redis_client.hgetall(session_key)

        if not session_data:
            return None

        # 最終アクセス時刻更新
        self.redis_client.hset(session_key, 'last_accessed', datetime.now().isoformat())
        self.redis_client.expire(session_key, self.default_ttl)

        return session_data

    def update_session(self, session_id, data):
        """セッションデータ更新"""
        session_key = f"session:{session_id}"
        self.redis_client.hset(session_key, 'data', json.dumps(data))
        self.redis_client.expire(session_key, self.default_ttl)

    def destroy_session(self, session_id):
        """セッション削除"""
        session_key = f"session:{session_id}"
        session_data = self.redis_client.hgetall(session_key)

        if session_data and 'user_id' in session_data:
            user_sessions_key = f"user_sessions:{session_data['user_id']}"
            self.redis_client.srem(user_sessions_key, session_id)

        self.redis_client.delete(session_key)

    def get_active_sessions_count(self):
        """アクティブセッション数取得"""
        pattern = "session:*"
        return len(list(self.redis_client.scan_iter(match=pattern)))

# 使用例
session_manager = RedisSessionManager('redis-host', 6379)

# セッション作成
session_id = session_manager.create_session(1001, {'theme': 'dark', 'language': 'ja'})

# セッション取得
session_data = session_manager.get_session(session_id)
print(f"Session data: {session_data}")
```

### 2.2 多階層キャッシュシステム

```python
#!/usr/bin/env python3
# cache_system.py

import redis
import json
import time
import hashlib
from enum import Enum
from typing import Optional, Any, Dict

class CacheLevel(Enum):
    L1_MEMORY = "l1"      # 最速・小容量
    L2_REDIS = "l2"       # 高速・中容量
    L3_DATABASE = "l3"    # 低速・大容量

class MultiLevelCache:
    def __init__(self, redis_host, redis_port):
        self.redis_client = redis.Redis(host=redis_host, port=redis_port)
        self.l1_cache = {}  # インメモリキャッシュ
        self.l1_max_size = 1000
        self.cache_stats = {
            'l1_hits': 0,
            'l2_hits': 0,
            'l3_hits': 0,
            'misses': 0
        }

    def _get_cache_key(self, key: str, prefix: str = "cache") -> str:
        """キャッシュキー生成"""
        return f"{prefix}:{hashlib.md5(key.encode()).hexdigest()}"

    def get(self, key: str, fetch_function=None) -> Optional[Any]:
        """多階層キャッシュから取得"""
        cache_key = self._get_cache_key(key)

        # L1キャッシュ確認
        if cache_key in self.l1_cache:
            self.cache_stats['l1_hits'] += 1
            return self.l1_cache[cache_key]['data']

        # L2キャッシュ（Redis）確認
        l2_data = self.redis_client.get(cache_key)
        if l2_data:
            self.cache_stats['l2_hits'] += 1
            data = json.loads(l2_data)
            # L1にプロモート
            self._set_l1_cache(cache_key, data)
            return data

        # L3（データベース）から取得
        if fetch_function:
            self.cache_stats['l3_hits'] += 1
            data = fetch_function()
            if data is not None:
                # 全レベルにキャッシュ
                self.set(key, data)
                return data

        self.cache_stats['misses'] += 1
        return None

    def set(self, key: str, data: Any, ttl: int = 3600):
        """全階層にキャッシュ設定"""
        cache_key = self._get_cache_key(key)
        json_data = json.dumps(data)

        # L1キャッシュ設定
        self._set_l1_cache(cache_key, data)

        # L2キャッシュ（Redis）設定
        self.redis_client.setex(cache_key, ttl, json_data)

        # メタデータ保存
        meta_key = f"meta:{cache_key}"
        metadata = {
            'created_at': time.time(),
            'ttl': ttl,
            'size': len(json_data)
        }
        self.redis_client.hset(meta_key, mapping=metadata)
        self.redis_client.expire(meta_key, ttl)

    def _set_l1_cache(self, key: str, data: Any):
        """L1キャッシュ設定（LRU）"""
        if len(self.l1_cache) >= self.l1_max_size:
            # LRU削除
            oldest_key = min(self.l1_cache.keys(),
                           key=lambda k: self.l1_cache[k]['accessed_at'])
            del self.l1_cache[oldest_key]

        self.l1_cache[key] = {
            'data': data,
            'accessed_at': time.time()
        }

    def invalidate(self, key: str):
        """キャッシュ無効化"""
        cache_key = self._get_cache_key(key)

        # L1から削除
        self.l1_cache.pop(cache_key, None)

        # L2から削除
        self.redis_client.delete(cache_key)
        self.redis_client.delete(f"meta:{cache_key}")

    def get_stats(self) -> Dict:
        """キャッシュ統計取得"""
        total_requests = sum(self.cache_stats.values())
        if total_requests == 0:
            return self.cache_stats

        stats = self.cache_stats.copy()
        stats['l1_hit_rate'] = stats['l1_hits'] / total_requests
        stats['l2_hit_rate'] = stats['l2_hits'] / total_requests
        stats['total_hit_rate'] = (stats['l1_hits'] + stats['l2_hits']) / total_requests

        return stats

# データ取得関数例
def fetch_user_from_db(user_id):
    """データベースからユーザー情報取得（模擬）"""
    time.sleep(0.1)  # データベースアクセス時間をシミュレート
    return {
        'id': user_id,
        'name': f'User {user_id}',
        'email': f'user{user_id}@example.com'
    }

# 使用例
cache = MultiLevelCache('redis-host', 6379)

# キャッシュを通してデータ取得
user_data = cache.get('user:1001', lambda: fetch_user_from_db(1001))
print(f"User data: {user_data}")

# 統計確認
print(f"Cache stats: {cache.get_stats()}")
```

### 2.3 リアルタイム分析システム

```python
#!/usr/bin/env python3
# realtime_analytics.py

import redis
import json
import time
from datetime import datetime, timedelta
from collections import defaultdict

class RealtimeAnalytics:
    def __init__(self, redis_host, redis_port):
        self.redis_client = redis.Redis(host=redis_host, port=redis_port)

    def track_event(self, event_type: str, user_id: str, properties: dict = None):
        """イベント追跡"""
        timestamp = int(time.time())
        minute_key = timestamp // 60 * 60  # 分単位のキー
        hour_key = timestamp // 3600 * 3600  # 時間単位のキー
        day_key = timestamp // 86400 * 86400  # 日単位のキー

        event_data = {
            'event_type': event_type,
            'user_id': user_id,
            'timestamp': timestamp,
            'properties': properties or {}
        }

        # 時系列イベントストリーム
        stream_key = f"events:{event_type}"
        self.redis_client.xadd(stream_key, event_data)

        # 分単位カウンター
        minute_counter_key = f"counter:minute:{event_type}:{minute_key}"
        self.redis_client.incr(minute_counter_key)
        self.redis_client.expire(minute_counter_key, 3600)  # 1時間保持

        # 時間単位カウンター
        hour_counter_key = f"counter:hour:{event_type}:{hour_key}"
        self.redis_client.incr(hour_counter_key)
        self.redis_client.expire(hour_counter_key, 86400 * 7)  # 7日保持

        # 日単位カウンター
        day_counter_key = f"counter:day:{event_type}:{day_key}"
        self.redis_client.incr(day_counter_key)
        self.redis_client.expire(day_counter_key, 86400 * 30)  # 30日保持

        # ユニークユーザー追跡（HyperLogLog）
        unique_users_key = f"unique:day:{event_type}:{day_key}"
        self.redis_client.pfadd(unique_users_key, user_id)
        self.redis_client.expire(unique_users_key, 86400 * 30)

        # リアルタイムランキング更新
        if event_type == "purchase":
            amount = properties.get('amount', 0)
            ranking_key = f"ranking:revenue:day:{day_key}"
            self.redis_client.zincrby(ranking_key, amount, user_id)
            self.redis_client.expire(ranking_key, 86400 * 30)

    def get_realtime_metrics(self, event_type: str, granularity: str = "minute", limit: int = 60):
        """リアルタイムメトリクス取得"""
        current_time = int(time.time())

        if granularity == "minute":
            interval = 60
            retention = 3600
        elif granularity == "hour":
            interval = 3600
            retention = 86400 * 7
        else:  # day
            interval = 86400
            retention = 86400 * 30

        metrics = []
        for i in range(limit):
            timestamp = current_time - (i * interval)
            aligned_timestamp = timestamp // interval * interval

            counter_key = f"counter:{granularity}:{event_type}:{aligned_timestamp}"
            count = self.redis_client.get(counter_key) or 0

            metrics.append({
                'timestamp': aligned_timestamp,
                'count': int(count)
            })

        return list(reversed(metrics))

    def get_unique_users(self, event_type: str, days: int = 7):
        """ユニークユーザー数取得"""
        current_time = int(time.time())
        day_key = current_time // 86400 * 86400

        unique_counts = []
        for i in range(days):
            target_day = day_key - (i * 86400)
            unique_users_key = f"unique:day:{event_type}:{target_day}"
            count = self.redis_client.pfcount(unique_users_key)

            unique_counts.append({
                'date': datetime.fromtimestamp(target_day).strftime('%Y-%m-%d'),
                'unique_users': count
            })

        return list(reversed(unique_counts))

    def get_top_users_by_revenue(self, days: int = 1, limit: int = 10):
        """売上別トップユーザー取得"""
        current_time = int(time.time())
        day_key = current_time // 86400 * 86400

        top_users = []
        for i in range(days):
            target_day = day_key - (i * 86400)
            ranking_key = f"ranking:revenue:day:{target_day}"

            # TOP N ユーザー取得（降順）
            users = self.redis_client.zrevrange(ranking_key, 0, limit-1, withscores=True)

            day_ranking = {
                'date': datetime.fromtimestamp(target_day).strftime('%Y-%m-%d'),
                'top_users': [{'user_id': user, 'revenue': score} for user, score in users]
            }
            top_users.append(day_ranking)

        return top_users

# 使用例
analytics = RealtimeAnalytics('redis-host', 6379)

# イベント追跡
analytics.track_event('page_view', 'user_1001', {'page': '/home'})
analytics.track_event('purchase', 'user_1001', {'amount': 1500, 'item': 'laptop'})

# リアルタイムメトリクス取得
page_view_metrics = analytics.get_realtime_metrics('page_view', 'minute', 60)
print(f"Page view metrics: {page_view_metrics[:5]}")  # 最新5分間
```

---

## ⚡ 第3章: Redis負荷テストとパフォーマンス最適化

### 3.1 Redis特化負荷テストスクリプト

```javascript
// redis-load-test.js
import redis from "k6/experimental/redis";

const client = redis.newClient("redis://redis-host:6379");

export let options = {
  stages: [
    { duration: "2m", target: 100 }, // 100 virtual users
    { duration: "5m", target: 100 }, // stay at 100
    { duration: "2m", target: 200 }, // ramp up to 200
    { duration: "5m", target: 200 }, // stay at 200
    { duration: "2m", target: 0 }, // ramp down
  ],
  thresholds: {
    redis_cmd_duration: ["p(95)<100"], // 95%のコマンドが100ms以内
    checks: ["rate>0.95"],
  },
};

export default function () {
  const userId = Math.floor(Math.random() * 10000) + 1;
  const sessionId = `session:${userId}:${Date.now()}`;

  // テストケース1: String操作（カウンター）
  const counterKey = `counter:user:${userId}`;
  client.incr(counterKey);
  client.expire(counterKey, 3600);

  // テストケース2: Hash操作（セッション管理）
  const sessionData = {
    user_id: userId.toString(),
    login_time: Date.now().toString(),
    last_activity: Date.now().toString(),
  };
  client.hset(sessionId, sessionData);
  client.expire(sessionId, 1800);

  // テストケース3: List操作（アクティビティログ）
  const activityKey = `activity:${userId}`;
  client.lpush(activityKey, `action:${Date.now()}`);
  client.ltrim(activityKey, 0, 99); // 最新100件のみ保持

  // テストケース4: Sorted Set操作（リーダーボード）
  const score = Math.floor(Math.random() * 1000) + 1;
  client.zadd("leaderboard:daily", score, `player:${userId}`);

  // テストケース5: Set操作（タグ管理）
  const tags = ["redis", "cache", "performance", "nosql"];
  const randomTag = tags[Math.floor(Math.random() * tags.length)];
  client.sadd(`user:${userId}:tags`, randomTag);

  // 読み取りテスト
  client.hgetall(sessionId);
  client.zrevrange("leaderboard:daily", 0, 9); // TOP10
  client.lrange(activityKey, 0, 9); // 最新10件
}

export function teardown() {
  client.close();
}
```

### 3.2 データ構造別パフォーマンステスト

```javascript
// redis-datatype-performance.js
import redis from "k6/experimental/redis";
import { check } from "k6";

const client = redis.newClient("redis://redis-host:6379");

export let options = {
  vus: 50,
  duration: "60s",
  thresholds: {
    redis_string_ops: ["p(95)<50"],
    redis_hash_ops: ["p(95)<100"],
    redis_list_ops: ["p(95)<150"],
    redis_set_ops: ["p(95)<100"],
    redis_zset_ops: ["p(95)<200"],
  },
};

export default function () {
  const testId = Math.floor(Math.random() * 1000);

  // String操作パフォーマンステスト
  const stringStart = Date.now();
  client.set(`string_test:${testId}`, "test_value");
  client.get(`string_test:${testId}`);
  client.incr(`counter:${testId}`);
  client.del(`string_test:${testId}`, `counter:${testId}`);
  const stringDuration = Date.now() - stringStart;

  // Hash操作パフォーマンステスト
  const hashStart = Date.now();
  client.hset(`hash_test:${testId}`, {
    field1: "value1",
    field2: "value2",
    field3: "value3",
  });
  client.hgetall(`hash_test:${testId}`);
  client.hdel(`hash_test:${testId}`, "field1");
  client.del(`hash_test:${testId}`);
  const hashDuration = Date.now() - hashStart;

  // List操作パフォーマンステスト
  const listStart = Date.now();
  client.lpush(`list_test:${testId}`, "item1", "item2", "item3");
  client.lrange(`list_test:${testId}`, 0, -1);
  client.rpop(`list_test:${testId}`);
  client.del(`list_test:${testId}`);
  const listDuration = Date.now() - listStart;

  // Set操作パフォーマンステスト
  const setStart = Date.now();
  client.sadd(`set_test:${testId}`, "member1", "member2", "member3");
  client.smembers(`set_test:${testId}`);
  client.sismember(`set_test:${testId}`, "member1");
  client.del(`set_test:${testId}`);
  const setDuration = Date.now() - setStart;

  // Sorted Set操作パフォーマンステスト
  const zsetStart = Date.now();
  client.zadd(
    `zset_test:${testId}`,
    100,
    "member1",
    200,
    "member2",
    150,
    "member3",
  );
  client.zrevrange(`zset_test:${testId}`, 0, -1);
  client.zrank(`zset_test:${testId}`, "member1");
  client.del(`zset_test:${testId}`);
  const zsetDuration = Date.now() - zsetStart;

  // パフォーマンス結果記録
  check(null, {
    "string ops under 50ms": () => stringDuration < 50,
    "hash ops under 100ms": () => hashDuration < 100,
    "list ops under 150ms": () => listDuration < 150,
    "set ops under 100ms": () => setDuration < 100,
    "zset ops under 200ms": () => zsetDuration < 200,
  });
}
```

### 3.3 Redisパフォーマンス最適化

#### メモリ最適化設定

```bash
# Redis設定最適化（redis.conf または Google Cloud Console）

# メモリ最適化
maxmemory-policy allkeys-lru          # LRU削除ポリシー
hash-max-ziplist-entries 512          # Hash圧縮閾値
hash-max-ziplist-value 64
list-max-ziplist-size -2               # List圧縮設定
set-max-intset-entries 512             # Set圧縮閾値
zset-max-ziplist-entries 128           # Sorted Set圧縮設定
zset-max-ziplist-value 64

# ネットワーク最適化
tcp-keepalive 60                       # TCP Keep-alive
tcp-backlog 511                        # TCP接続バックログ
timeout 0                              # クライアントタイムアウト（0=無制限）

# パフォーマンス最適化
save 900 1 300 10 60 10000            # RDB保存条件
stop-writes-on-bgsave-error yes        # 保存エラー時の書き込み停止
rdbcompression yes                     # RDB圧縮
rdbchecksum yes                        # RDBチェックサム

# AOF設定（耐久性重視の場合）
appendonly yes                         # AOF有効化
appendfsync everysec                   # 1秒ごとのfsync
no-appendfsync-on-rewrite no           # 書き換え中のfsync制御
auto-aof-rewrite-percentage 100        # AOF自動書き換え
auto-aof-rewrite-min-size 64mb
```

#### パフォーマンス監視クエリ

```bash
# 基本統計情報
redis-cli INFO stats
redis-cli INFO memory
redis-cli INFO clients
redis-cli INFO replication

# スロークエリ確認
redis-cli SLOWLOG GET 10
redis-cli SLOWLOG LEN
redis-cli CONFIG GET slowlog-log-slower-than

# メモリ使用量詳細
redis-cli MEMORY USAGE key_name
redis-cli MEMORY STATS
redis-cli MEMORY DOCTOR

# クライアント接続情報
redis-cli CLIENT LIST
redis-cli INFO clients

# キー分析
redis-cli --bigkeys            # 大きなキーの特定
redis-cli --memkeys            # メモリ使用量順
redis-cli --hotkeys            # アクセス頻度順（要設定）
```

---

## 📊 第4章: Redis高可用性とクラスタリング

### 4.1 Redis Sentinel（高可用性）

```python
#!/usr/bin/env python3
# redis_sentinel_manager.py

import redis.sentinel
import logging
import time
from typing import List, Optional

class RedisSentinelManager:
    def __init__(self, sentinel_hosts: List[tuple], service_name: str = 'mymaster'):
        """
        Redis Sentinel接続管理

        Args:
            sentinel_hosts: [(host, port), ...] のリスト
            service_name: Sentinelで管理されるサービス名
        """
        self.sentinel_hosts = sentinel_hosts
        self.service_name = service_name
        self.sentinel = redis.sentinel.Sentinel(sentinel_hosts)
        self.logger = logging.getLogger(__name__)

    def get_master(self):
        """マスターRedis接続取得"""
        try:
            master = self.sentinel.master_for(
                self.service_name,
                socket_timeout=0.1,
                password=None,
                db=0
            )
            return master
        except Exception as e:
            self.logger.error(f"Master connection failed: {e}")
            return None

    def get_slave(self):
        """スレーブRedis接続取得（読み取り専用）"""
        try:
            slave = self.sentinel.slave_for(
                self.service_name,
                socket_timeout=0.1,
                password=None,
                db=0
            )
            return slave
        except Exception as e:
            self.logger.error(f"Slave connection failed: {e}")
            return None

    def get_master_info(self):
        """マスター情報取得"""
        try:
            return self.sentinel.discover_master(self.service_name)
        except Exception as e:
            self.logger.error(f"Master discovery failed: {e}")
            return None

    def get_slaves_info(self):
        """スレーブ情報取得"""
        try:
            return self.sentinel.discover_slaves(self.service_name)
        except Exception as e:
            self.logger.error(f"Slaves discovery failed: {e}")
            return []

    def wait_for_master(self, timeout: int = 30):
        """マスター復旧待機"""
        start_time = time.time()
        while time.time() - start_time < timeout:
            master_info = self.get_master_info()
            if master_info:
                self.logger.info(f"Master available: {master_info}")
                return True
            time.sleep(1)

        self.logger.error("Master not available within timeout")
        return False

# 使用例
sentinel_hosts = [
    ('sentinel1.example.com', 26379),
    ('sentinel2.example.com', 26379),
    ('sentinel3.example.com', 26379)
]

sentinel_manager = RedisSentinelManager(sentinel_hosts)

# 読み書き分離
def write_data(key, value):
    master = sentinel_manager.get_master()
    if master:
        return master.set(key, value)
    return False

def read_data(key):
    # 読み取りはスレーブから
    slave = sentinel_manager.get_slave()
    if slave:
        return slave.get(key)

    # スレーブが利用できない場合はマスターから
    master = sentinel_manager.get_master()
    if master:
        return master.get(key)

    return None
```

### 4.2 Redis Cluster（シャーディング）

```python
#!/usr/bin/env python3
# redis_cluster_manager.py

from rediscluster import RedisCluster
import redis
import hashlib
import logging
from typing import List, Any, Optional

class RedisClusterManager:
    def __init__(self, cluster_nodes: List[dict]):
        """
        Redis Cluster接続管理

        Args:
            cluster_nodes: [{'host': 'node1', 'port': 7000}, ...]
        """
        self.cluster_nodes = cluster_nodes
        self.cluster = RedisCluster(
            startup_nodes=cluster_nodes,
            decode_responses=True,
            skip_full_coverage_check=True,
            health_check_interval=30
        )
        self.logger = logging.getLogger(__name__)

    def get_cluster_info(self):
        """クラスター情報取得"""
        try:
            return self.cluster.cluster_info()
        except Exception as e:
            self.logger.error(f"Cluster info failed: {e}")
            return None

    def get_cluster_nodes(self):
        """クラスターノード情報取得"""
        try:
            return self.cluster.cluster_nodes()
        except Exception as e:
            self.logger.error(f"Cluster nodes failed: {e}")
            return None

    def hash_tag_operation(self, base_key: str, operations: List[dict]):
        """
        ハッシュタグを使用した同一ノード操作

        Args:
            base_key: ベースキー
            operations: [{'op': 'set', 'key': 'key1', 'value': 'val1'}, ...]
        """
        # ハッシュタグでキーを修正（同一スロットに配置）
        hash_tag = f"{{{base_key}}}"

        try:
            pipe = self.cluster.pipeline()

            for op in operations:
                tagged_key = f"{hash_tag}:{op['key']}"

                if op['op'] == 'set':
                    pipe.set(tagged_key, op['value'])
                elif op['op'] == 'get':
                    pipe.get(tagged_key)
                elif op['op'] == 'hset':
                    pipe.hset(tagged_key, mapping=op['data'])
                # 他の操作も追加可能

            return pipe.execute()
        except Exception as e:
            self.logger.error(f"Hash tag operation failed: {e}")
            return None

    def multi_key_operation(self, operations: dict):
        """
        複数キーにまたがる操作（パフォーマンス考慮）

        Args:
            operations: {'key1': 'value1', 'key2': 'value2', ...}
        """
        try:
            # msetはクラスターでは使用不可、個別に設定
            pipe = self.cluster.pipeline()
            for key, value in operations.items():
                pipe.set(key, value)
            return pipe.execute()
        except Exception as e:
            self.logger.error(f"Multi-key operation failed: {e}")
            return None

    def get_slot_info(self, key: str):
        """キーのスロット情報取得"""
        slot = self.cluster.connection_pool.nodes.keyslot(key)
        node = self.cluster.connection_pool.get_node_by_slot(slot)
        return {
            'key': key,
            'slot': slot,
            'node': f"{node.host}:{node.port}" if node else None
        }

# 使用例
cluster_nodes = [
    {'host': 'cluster-node1.example.com', 'port': 7000},
    {'host': 'cluster-node2.example.com', 'port': 7000},
    {'host': 'cluster-node3.example.com', 'port': 7000}
]

cluster_manager = RedisClusterManager(cluster_nodes)

# クラスター状態確認
cluster_info = cluster_manager.get_cluster_info()
print(f"Cluster info: {cluster_info}")

# ハッシュタグを使用した関連データの同一ノード配置
operations = [
    {'op': 'set', 'key': 'name', 'value': 'John Doe'},
    {'op': 'set', 'key': 'email', 'value': 'john@example.com'},
    {'op': 'hset', 'key': 'profile', 'data': {'age': 30, 'city': 'Tokyo'}}
]
cluster_manager.hash_tag_operation('user:1001', operations)
```

### 4.3 障害復旧シミュレーション

```bash
#!/bin/bash
# redis_failover_test.sh

echo "=== Redis 障害復旧テスト ==="

REDIS_MASTER_HOST="redis-master.example.com"
REDIS_SLAVE_HOST="redis-slave.example.com"
SENTINEL_HOST="redis-sentinel.example.com"

# 1. 初期状態確認
echo "1. 初期状態確認"
redis-cli -h $REDIS_MASTER_HOST ping
redis-cli -h $REDIS_SLAVE_HOST ping
redis-cli -h $SENTINEL_HOST -p 26379 ping

# 2. テストデータ投入
echo "2. テストデータ投入"
for i in {1..100}; do
    redis-cli -h $REDIS_MASTER_HOST set "test_key_$i" "test_value_$i"
done

# 3. レプリケーション確認
echo "3. レプリケーション確認"
redis-cli -h $REDIS_SLAVE_HOST get "test_key_50"

# 4. マスター障害シミュレーション
echo "4. マスター障害シミュレーション"
# GCPコンソールまたはTerraformでインスタンス停止

# 5. Sentinelによるフェイルオーバー監視
echo "5. フェイルオーバー監視"
while true; do
    MASTER_INFO=$(redis-cli -h $SENTINEL_HOST -p 26379 sentinel masters | head -20)
    echo "Current master info: $MASTER_INFO"
    sleep 5

    # 新しいマスターが決定されたかチェック
    NEW_MASTER=$(redis-cli -h $SENTINEL_HOST -p 26379 sentinel get-master-addr-by-name mymaster)
    if [[ "$NEW_MASTER" != "$REDIS_MASTER_HOST 6379" ]]; then
        echo "フェイルオーバー完了: 新マスター = $NEW_MASTER"
        break
    fi
done

# 6. データ整合性確認
echo "6. データ整合性確認"
redis-cli -h $NEW_MASTER get "test_key_50"

# 7. 旧マスター復旧テスト
echo "7. 旧マスター復旧テスト"
# GCPコンソールでインスタンス再起動

echo "障害復旧テスト完了"
```

---

## 📈 第5章: Redis監視・運用・トラブルシューティング

### 5.1 Redis監視スクリプト

```python
#!/usr/bin/env python3
# redis_monitoring.py

import redis
import time
import json
import smtplib
from datetime import datetime
from email.mime.text import MimeText
from typing import Dict, List, Any

class RedisMonitor:
    def __init__(self, redis_host: str, redis_port: int = 6379):
        self.redis_client = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
        self.alerts = []

        # 閾値設定
        self.thresholds = {
            'memory_usage_percent': 85,
            'cpu_usage_percent': 80,
            'connected_clients': 1000,
            'blocked_clients': 10,
            'keyspace_misses_rate': 0.1,  # 10%以上
            'slow_log_count': 100,
            'last_save_time': 3600,  # 1時間
        }

    def get_info_metrics(self) -> Dict[str, Any]:
        """Redis INFO コマンドから主要メトリクス取得"""
        info = self.redis_client.info()

        metrics = {
            # メモリ関連
            'used_memory': info.get('used_memory', 0),
            'used_memory_peak': info.get('used_memory_peak', 0),
            'used_memory_rss': info.get('used_memory_rss', 0),
            'mem_fragmentation_ratio': info.get('mem_fragmentation_ratio', 0),

            # クライアント関連
            'connected_clients': info.get('connected_clients', 0),
            'blocked_clients': info.get('blocked_clients', 0),
            'client_recent_max_input_buffer': info.get('client_recent_max_input_buffer', 0),

            # 統計関連
            'total_connections_received': info.get('total_connections_received', 0),
            'total_commands_processed': info.get('total_commands_processed', 0),
            'instantaneous_ops_per_sec': info.get('instantaneous_ops_per_sec', 0),
            'keyspace_hits': info.get('keyspace_hits', 0),
            'keyspace_misses': info.get('keyspace_misses', 0),

            # 永続化関連
            'last_save_time': info.get('last_save_time', 0),
            'bgsave_in_progress': info.get('bgsave_in_progress', 0),
            'aof_enabled': info.get('aof_enabled', 0),
            'aof_rewrite_in_progress': info.get('aof_rewrite_in_progress', 0),

            # レプリケーション関連
            'role': info.get('role', 'unknown'),
            'connected_slaves': info.get('connected_slaves', 0),
            'master_repl_offset': info.get('master_repl_offset', 0),
            'repl_backlog_size': info.get('repl_backlog_size', 0),
        }

        # キャッシュヒット率計算
        total_ops = metrics['keyspace_hits'] + metrics['keyspace_misses']
        if total_ops > 0:
            metrics['hit_rate'] = metrics['keyspace_hits'] / total_ops
            metrics['miss_rate'] = metrics['keyspace_misses'] / total_ops
        else:
            metrics['hit_rate'] = 1.0
            metrics['miss_rate'] = 0.0

        return metrics

    def check_slow_log(self) -> List[Dict]:
        """スロークエリログチェック"""
        try:
            slow_log = self.redis_client.slowlog_get(10)
            slow_queries = []

            for entry in slow_log:
                slow_queries.append({
                    'id': entry['id'],
                    'duration_us': entry['duration'],
                    'duration_ms': entry['duration'] / 1000,
                    'command': ' '.join(entry['command']),
                    'timestamp': datetime.fromtimestamp(entry['start_time']).isoformat()
                })

            return slow_queries
        except Exception as e:
            self.alerts.append(f"Slow log check failed: {e}")
            return []

    def check_memory_analysis(self) -> Dict[str, Any]:
        """メモリ使用量詳細分析"""
        try:
            memory_info = {}

            # メモリ統計
            memory_stats = self.redis_client.memory_stats()
            memory_info['stats'] = memory_stats

            # 大きなキーの特定（サンプリング）
            big_keys = []
            sample_keys = list(self.redis_client.scan_iter(count=1000))[:100]

            for key in sample_keys:
                try:
                    memory_usage = self.redis_client.memory_usage(key)
                    if memory_usage and memory_usage > 1024 * 1024:  # 1MB以上
                        big_keys.append({
                            'key': key,
                            'size_bytes': memory_usage,
                            'size_mb': round(memory_usage / 1024 / 1024, 2),
                            'type': self.redis_client.type(key),
                            'ttl': self.redis_client.ttl(key)
                        })
                except:
                    continue

            memory_info['big_keys'] = sorted(big_keys, key=lambda x: x['size_bytes'], reverse=True)[:10]

            return memory_info
        except Exception as e:
            self.alerts.append(f"Memory analysis failed: {e}")
            return {}

    def check_alerts(self, metrics: Dict[str, Any]) -> List[str]:
        """アラート条件チェック"""
        alerts = []

        # メモリ使用率アラート
        if 'used_memory' in metrics and 'used_memory_peak' in metrics:
            memory_usage_ratio = metrics['used_memory'] / max(metrics['used_memory_peak'], 1)
            if memory_usage_ratio > self.thresholds['memory_usage_percent'] / 100:
                alerts.append(f"High memory usage: {memory_usage_ratio*100:.1f}%")

        # クライアント接続数アラート
        if metrics['connected_clients'] > self.thresholds['connected_clients']:
            alerts.append(f"High client connections: {metrics['connected_clients']}")

        # ブロックされたクライアント
        if metrics['blocked_clients'] > self.thresholds['blocked_clients']:
            alerts.append(f"Many blocked clients: {metrics['blocked_clients']}")

        # キャッシュミス率
        if metrics['miss_rate'] > self.thresholds['keyspace_misses_rate']:
            alerts.append(f"High cache miss rate: {metrics['miss_rate']*100:.1f}%")

        # 最終保存時刻
        current_time = int(time.time())
        if current_time - metrics['last_save_time'] > self.thresholds['last_save_time']:
            alerts.append(f"Long time since last save: {(current_time - metrics['last_save_time']) // 60} minutes")

        return alerts

    def generate_report(self) -> Dict[str, Any]:
        """監視レポート生成"""
        report = {
            'timestamp': datetime.now().isoformat(),
            'metrics': self.get_info_metrics(),
            'slow_queries': self.check_slow_log(),
            'memory_analysis': self.check_memory_analysis(),
            'alerts': []
        }

        # アラートチェック
        alerts = self.check_alerts(report['metrics'])
        report['alerts'] = alerts

        return report

    def run_monitoring_loop(self, interval: int = 60):
        """監視ループ実行"""
        while True:
            try:
                report = self.generate_report()

                # レポート出力
                print(f"\n=== Redis Monitoring Report - {report['timestamp']} ===")
                print(f"Connected Clients: {report['metrics']['connected_clients']}")
                print(f"Memory Usage: {report['metrics']['used_memory'] // 1024 // 1024} MB")
                print(f"Cache Hit Rate: {report['metrics']['hit_rate']*100:.2f}%")
                print(f"Operations/sec: {report['metrics']['instantaneous_ops_per_sec']}")

                # アラート表示
                if report['alerts']:
                    print("\n🚨 ALERTS:")
                    for alert in report['alerts']:
                        print(f"  - {alert}")

                # スロークエリ表示
                if report['slow_queries']:
                    print(f"\n⚠️  Slow Queries: {len(report['slow_queries'])}")
                    for query in report['slow_queries'][:3]:
                        print(f"  - {query['duration_ms']:.2f}ms: {query['command'][:100]}")

                time.sleep(interval)

            except KeyboardInterrupt:
                print("\nMonitoring stopped")
                break
            except Exception as e:
                print(f"Monitoring error: {e}")
                time.sleep(interval)

# 使用例
if __name__ == "__main__":
    monitor = RedisMonitor('redis-host', 6379)

    # 一回限りのレポート
    report = monitor.generate_report()
    print(json.dumps(report, indent=2, ensure_ascii=False))

    # 継続監視
    # monitor.run_monitoring_loop(60)  # 60秒間隔
```

### 5.2 Redis運用自動化スクリプト

```bash
#!/bin/bash
# redis_maintenance.sh

LOG_FILE="/var/log/redis-maintenance.log"
REDIS_HOST="redis-host"
REDIS_PORT="6379"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$DATE] $1" | tee -a $LOG_FILE
}

redis_cmd() {
    redis-cli -h $REDIS_HOST -p $REDIS_PORT "$@"
}

log "Starting Redis maintenance"

# 1. 基本ヘルスチェック
log "1. Health check"
if ! redis_cmd ping > /dev/null 2>&1; then
    log "ERROR: Redis not responding"
    exit 1
fi

# 2. メモリ使用量チェック
log "2. Memory usage check"
MEMORY_INFO=$(redis_cmd info memory | grep used_memory_human)
log "Memory usage: $MEMORY_INFO"

# 3. スロークエリログ分析
log "3. Slow query analysis"
SLOW_LOG_COUNT=$(redis_cmd slowlog len)
log "Slow queries count: $SLOW_LOG_COUNT"

if [ "$SLOW_LOG_COUNT" -gt 100 ]; then
    log "WARNING: High slow query count"
    redis_cmd slowlog get 5 >> $LOG_FILE
fi

# 4. キー有効期限チェック（期限切れキーのクリーンアップ）
log "4. Expired keys cleanup"
EXPIRED_KEYS=$(redis_cmd info stats | grep expired_keys | cut -d: -f2)
log "Expired keys: $EXPIRED_KEYS"

# 5. バックアップ実行
log "5. Creating backup"
redis_cmd bgsave
sleep 5

# バックアップ完了待機
while [ "$(redis_cmd lastsave)" == "$(redis_cmd lastsave)" ]; do
    sleep 1
done
log "Backup completed"

# 6. メモリ断片化チェック
log "6. Memory fragmentation check"
FRAGMENTATION=$(redis_cmd info memory | grep mem_fragmentation_ratio | cut -d: -f2)
log "Memory fragmentation ratio: $FRAGMENTATION"

# 断片化が高い場合の警告
if (( $(echo "$FRAGMENTATION > 2.0" | bc -l) )); then
    log "WARNING: High memory fragmentation ($FRAGMENTATION)"
fi

# 7. クライアント接続監視
log "7. Client connections monitoring"
CLIENT_INFO=$(redis_cmd info clients)
log "Client info: $CLIENT_INFO"

# 8. レプリケーション状態確認（該当する場合）
log "8. Replication status check"
REPL_INFO=$(redis_cmd info replication)
log "Replication info: $REPL_INFO"

# 9. パフォーマンス統計レポート
log "9. Performance statistics"
redis_cmd info stats | grep -E "(instantaneous_ops_per_sec|keyspace_hits|keyspace_misses)" >> $LOG_FILE

# 10. 不要なキーのクリーンアップ（TTLが設定されていない一時キー）
log "10. Cleanup temporary keys"
# 注意: 本番環境では慎重に実行
TEMP_KEYS=$(redis_cmd --scan --pattern "temp:*" | wc -l)
log "Temporary keys found: $TEMP_KEYS"

log "Redis maintenance completed"

# アラート送信（必要に応じて）
if [ "$SLOW_LOG_COUNT" -gt 1000 ] || (( $(echo "$FRAGMENTATION > 3.0" | bc -l) )); then
    echo "Redis maintenance alert: Check $LOG_FILE" | mail -s "Redis Alert" admin@example.com
fi
```

---

## 🎯 第6章: Redis実践課題

### 6.1 実践課題1: 分散ロック実装

**シナリオ**: 在庫管理システムで同時購入の競合状態を防ぐ

```python
#!/usr/bin/env python3
# distributed_lock.py

import redis
import uuid
import time
import random
from contextlib import contextmanager

class RedisDistributedLock:
    def __init__(self, redis_client, key, timeout=10, retry_delay=0.1):
        self.redis_client = redis_client
        self.key = key
        self.timeout = timeout
        self.retry_delay = retry_delay
        self.identifier = str(uuid.uuid4())

    def acquire(self):
        """ロック取得"""
        end_time = time.time() + self.timeout

        while time.time() < end_time:
            # SET NX EX でアトミックにロック取得
            if self.redis_client.set(self.key, self.identifier, nx=True, ex=self.timeout):
                return True

            time.sleep(self.retry_delay)

        return False

    def release(self):
        """ロック解放"""
        # Luaスクリプトでアトミックな解放
        lua_script = """
        if redis.call("GET", KEYS[1]) == ARGV[1] then
            return redis.call("DEL", KEYS[1])
        else
            return 0
        end
        """
        return self.redis_client.eval(lua_script, 1, self.key, self.identifier)

    @contextmanager
    def __call__(self):
        """コンテキストマネージャーとして使用"""
        acquired = self.acquire()
        if not acquired:
            raise Exception(f"Failed to acquire lock: {self.key}")

        try:
            yield
        finally:
            self.release()

# 在庫管理システム例
class InventoryManager:
    def __init__(self, redis_client):
        self.redis_client = redis_client

    def purchase_item(self, item_id, quantity, user_id):
        """商品購入（分散ロック使用）"""
        lock_key = f"lock:inventory:{item_id}"

        with RedisDistributedLock(self.redis_client, lock_key):
            # 現在の在庫確認
            current_stock = int(self.redis_client.get(f"stock:{item_id}") or 0)

            if current_stock < quantity:
                return {
                    'success': False,
                    'message': f'Insufficient stock. Available: {current_stock}'
                }

            # 在庫減算
            new_stock = current_stock - quantity
            self.redis_client.set(f"stock:{item_id}", new_stock)

            # 購入履歴記録
            purchase_data = {
                'user_id': user_id,
                'item_id': item_id,
                'quantity': quantity,
                'timestamp': time.time()
            }
            self.redis_client.lpush(f"purchases:{item_id}", str(purchase_data))

            return {
                'success': True,
                'message': f'Purchase successful. Remaining stock: {new_stock}'
            }

# 負荷テストシミュレーション
def simulate_concurrent_purchases():
    redis_client = redis.Redis(host='redis-host', port=6379, decode_responses=True)
    inventory = InventoryManager(redis_client)

    # 初期在庫設定
    redis_client.set("stock:item_001", 100)

    # 同時購入シミュレーション
    import threading

    def purchase_worker(worker_id):
        for i in range(10):
            result = inventory.purchase_item('item_001', 1, f'user_{worker_id}_{i}')
            print(f"Worker {worker_id}: {result}")
            time.sleep(random.uniform(0.1, 0.5))

    # 10個のワーカーで同時実行
    threads = []
    for i in range(10):
        thread = threading.Thread(target=purchase_worker, args=(i,))
        threads.append(thread)
        thread.start()

    for thread in threads:
        thread.join()

    # 最終在庫確認
    final_stock = redis_client.get("stock:item_001")
    print(f"Final stock: {final_stock}")

if __name__ == "__main__":
    simulate_concurrent_purchases()
```

**課題**: 上記のコードを拡張して以下を実装してください：

1. ロックの自動延長機能
2. デッドロック検出機能
3. 複数商品の一括購入機能

### 6.2 実践課題2: リアルタイムリーダーボード

```python
#!/usr/bin/env python3
# realtime_leaderboard.py

import redis
import time
import json
from datetime import datetime, timedelta

class RealtimeLeaderboard:
    def __init__(self, redis_client):
        self.redis_client = redis_client

    def add_score(self, user_id, score, game_mode="default"):
        """スコア追加"""
        timestamp = int(time.time())

        # 全期間ランキング
        all_time_key = f"leaderboard:{game_mode}:all_time"
        self.redis_client.zadd(all_time_key, {user_id: score})

        # 日別ランキング
        daily_key = f"leaderboard:{game_mode}:daily:{timestamp // 86400 * 86400}"
        self.redis_client.zadd(daily_key, {user_id: score})
        self.redis_client.expire(daily_key, 86400 * 7)  # 7日間保持

        # 週別ランキング
        week_start = timestamp // (86400 * 7) * (86400 * 7)
        weekly_key = f"leaderboard:{game_mode}:weekly:{week_start}"
        self.redis_client.zadd(weekly_key, {user_id: score})
        self.redis_client.expire(weekly_key, 86400 * 30)  # 30日間保持

        # ユーザーのスコア履歴
        user_history_key = f"user_scores:{user_id}:{game_mode}"
        score_data = json.dumps({'score': score, 'timestamp': timestamp})
        self.redis_client.lpush(user_history_key, score_data)
        self.redis_client.ltrim(user_history_key, 0, 99)  # 最新100件のみ

    def get_ranking(self, game_mode="default", period="all_time", limit=100):
        """ランキング取得"""
        # あなたのタスク: 実装してください
        pass

    def get_user_rank(self, user_id, game_mode="default", period="all_time"):
        """ユーザーの順位取得"""
        # あなたのタスク: 実装してください
        pass

    def get_nearby_users(self, user_id, game_mode="default", range_size=5):
        """ユーザー周辺の順位取得"""
        # あなたのタスク: 実装してください
        pass

# 課題: 上記のメソッドを実装し、以下の機能を追加してください：
# 1. リアルタイム順位変動通知
# 2. 複数ゲームモードの統合ランキング
# 3. ランキングのアーカイブ機能
```

### 6.3 実践課題3: Pub/Subチャットシステム

```python
#!/usr/bin/env python3
# chat_system.py

import redis
import json
import threading
import time
from datetime import datetime

class RedisChatSystem:
    def __init__(self, redis_host, redis_port=6379):
        self.redis_client = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
        self.pubsub = self.redis_client.pubsub()
        self.listeners = {}

    def send_message(self, channel, user_id, message, message_type="text"):
        """メッセージ送信"""
        # あなたのタスク: 実装してください
        # ヒント:
        # - Pub/Sub での配信
        # - メッセージ履歴の保存
        # - オンラインユーザーの管理
        pass

    def join_channel(self, channel, user_id, callback):
        """チャンネル参加"""
        # あなたのタスク: 実装してください
        pass

    def leave_channel(self, channel, user_id):
        """チャンネル退出"""
        # あなたのタスク: 実装してください
        pass

    def get_message_history(self, channel, limit=50):
        """メッセージ履歴取得"""
        # あなたのタスク: 実装してください
        pass

# 課題: 上記のクラスを完成させ、以下の機能を実装してください：
# 1. プライベートメッセージ機能
# 2. 既読・未読管理
# 3. メッセージの暗号化
# 4. スパム防止機能（レート制限）
```

### 6.4 Redis DBA スキルチェックリスト

#### 基礎レベル ✅

- [ ] 基本的なRedisデータ型操作（String, Hash, List, Set, Sorted Set）
- [ ] TTL設定とキー管理
- [ ] redis-cli の基本操作
- [ ] Redis設定ファイルの理解

#### 中級レベル ⭐

- [ ] Pub/Sub メッセージング
- [ ] Lua スクリプティング
- [ ] トランザクション（MULTI/EXEC）
- [ ] パイプライン処理
- [ ] メモリ最適化設定
- [ ] 永続化戦略（RDB/AOF）

#### 上級レベル 🚀

- [ ] Redis Cluster設計・運用
- [ ] Redis Sentinel設定・管理
- [ ] 分散ロック実装
- [ ] 高負荷環境でのパフォーマンスチューニング
- [ ] カスタムモジュール開発

#### エキスパートレベル 🎯

- [ ] 大規模システムでのRedis設計
- [ ] マルチリージョン構成
- [ ] 災害復旧戦略
- [ ] セキュリティ強化
- [ ] Redis内部アーキテクチャの深い理解

---

## 📖 継続学習リソース

### Redis特化リソース

#### 必読書籍

- 「Redis in Action」
- 「Redis実践入門」
- 「High Performance Redis」

#### 公式ドキュメント

- [Redis Documentation](https://redis.io/docs/)
- [Redis Commands Reference](https://redis.io/commands/)
- [Redis Modules](https://redis.io/docs/modules/)

#### コミュニティ・ブログ

- [Redis Blog](https://redis.com/blog/)
- [Redis Weekly](https://redisweekly.com/)
- [Redis Labs Resources](https://redis.com/resources/)

#### 実践環境

- [Try Redis](https://try.redis.io/)
- [Redis Docker Images](https://hub.docker.com/_/redis)
- [Redis Cloud](https://redis.com/redis-enterprise-cloud/)

### 関連技術スタック

#### 監視・運用ツール

- **Redis Commander**: Web GUI
- **RedisInsight**: 公式GUI管理ツール
- **redis-stat**: リアルタイム統計
- **RedisLive**: ライブ監視ダッシュボード

#### Redis エコシステム

- **RedisJSON**: JSON操作モジュール
- **RediSearch**: 全文検索エンジン
- **RedisTimeSeries**: 時系列データベース
- **RedisGraph**: グラフデータベース
- **RedisML**: 機械学習モジュール

---

## 🎯 総括

本RedisハンズオンでSQLデータベースとは根本的に異なる以下の技術を習得しました：

### 🔑 核心技術

1. **インメモリアーキテクチャ**: 高速アクセスとTTL管理
2. **多様なデータ構造**: 用途別最適化された6つの基本型
3. **Pub/Subメッセージング**: リアルタイム通信基盤
4. **分散システム対応**: Cluster、Sentinel による高可用性
5. **Lua スクリプティング**: アトミックな複合操作

### 💡 実践的応用

- **キャッシング戦略**: 多階層キャッシュシステム
- **セッション管理**: 分散セッションストア
- **リアルタイム分析**: イベント処理とメトリクス収集
- **分散ロック**: 競合状態の回避
- **ランキングシステム**: Sorted Set活用

### 🚀 システム設計力

- **パフォーマンス最適化**: メモリ効率とレスポンス時間
- **高可用性設計**: 障害耐性と自動フェイルオーバー
- **運用監視**: プロアクティブな問題検出
- **スケーラビリティ**: 水平分散とシャーディング

### 🔄 次のステップ

Redis は単なるキャッシュを超えて、**データ構造サーバー**として多様な用途に活用できます：

- **IoT・リアルタイム処理**: Redis Streams + TimeSeries
- **機械学習**: RedisML での推論エンジン
- **検索エンジン**: RediSearch での全文検索
- **グラフ分析**: RedisGraph でのソーシャル分析

**Redisマスターとして、高性能・リアルタイムシステムの心臓部を支える技術者を目指してください！**

---

> **関連ハンズオン**
>
> - [MySQL版ハンズオン](./mysql.md) - リレーショナルデータベース基礎
> - [PostgreSQL版ハンズオン](./postgresql.md) - 高機能RDBMSの活用
> - MongoDB版ハンズオン（予定）- ドキュメントデータベース
> - Elasticsearch版ハンズオン（予定）- 検索・分析エンジン
