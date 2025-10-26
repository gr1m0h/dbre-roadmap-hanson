#!/usr/bin/env python3
"""
Redis Sentinel 管理システム

使用方法:
    from sentinel_manager import RedisSentinelManager
    
    sentinel_hosts = [
        ('sentinel1.example.com', 26379),
        ('sentinel2.example.com', 26379),
        ('sentinel3.example.com', 26379)
    ]
    
    sentinel_manager = RedisSentinelManager(sentinel_hosts)
    master = sentinel_manager.get_master()
"""

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
if __name__ == "__main__":
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
