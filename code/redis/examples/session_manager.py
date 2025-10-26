#!/usr/bin/env python3
"""
Redis セッション管理システム

使用方法:
    from session_manager import RedisSessionManager
    
    manager = RedisSessionManager('redis-host', 6379)
    session_id = manager.create_session(1001, {'theme': 'dark'})
    session_data = manager.get_session(session_id)
"""

import redis
import json
import uuid
from datetime import datetime

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
            'data': json.dumps(user_data or {})
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
if __name__ == "__main__":
    session_manager = RedisSessionManager('localhost', 6379)
    
    # セッション作成
    session_id = session_manager.create_session(1001, {'theme': 'dark', 'language': 'ja'})
    print(f"Created session: {session_id}")
    
    # セッション取得
    session_data = session_manager.get_session(session_id)
    print(f"Session data: {session_data}")
    
    # アクティブセッション数
    print(f"Active sessions: {session_manager.get_active_sessions_count()}")
