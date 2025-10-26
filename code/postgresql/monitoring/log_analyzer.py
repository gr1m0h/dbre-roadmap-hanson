#!/usr/bin/env python3
"""
PostgreSQL ログ分析ツール

使用方法:
    python log_analyzer.py /var/log/postgresql/postgresql.log
"""

import re
import csv
from datetime import datetime
from collections import defaultdict, Counter
import argparse

class PostgreSQLLogAnalyzer:
    def __init__(self, log_file):
        self.log_file = log_file
        self.errors = []
        self.slow_queries = []
        self.connections = defaultdict(int)
        self.query_patterns = Counter()
        
    def parse_log(self):
        """ログファイルを解析"""
        error_pattern = re.compile(r'ERROR:|FATAL:|PANIC:')
        slow_query_pattern = re.compile(r'duration: (\d+\.\d+) ms')
        connection_pattern = re.compile(r'connection (authorized|received)')
        
        with open(self.log_file, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                # エラー検出
                if error_pattern.search(line):
                    self.errors.append(line.strip())
                
                # スロークエリ検出
                slow_match = slow_query_pattern.search(line)
                if slow_match:
                    duration = float(slow_match.group(1))
                    if duration > 1000:  # 1秒以上
                        self.slow_queries.append({
                            'duration': duration,
                            'line': line.strip()
                        })
                
                # 接続パターン分析
                if connection_pattern.search(line):
                    user_match = re.search(r'user=(\w+)', line)
                    if user_match:
                        self.connections[user_match.group(1)] += 1
    
    def analyze_errors(self):
        """エラー分析"""
        print("=" * 80)
        print("エラー分析")
        print("=" * 80)
        
        error_types = Counter()
        for error in self.errors:
            if 'deadlock' in error.lower():
                error_types['Deadlock'] += 1
            elif 'connection' in error.lower():
                error_types['Connection Error'] += 1
            elif 'syntax' in error.lower():
                error_types['Syntax Error'] += 1
            elif 'permission' in error.lower():
                error_types['Permission Denied'] += 1
            else:
                error_types['Other'] += 1
        
        print(f"\n総エラー数: {len(self.errors)}")
        print("\nエラータイプ別集計:")
        for error_type, count in error_types.most_common():
            print(f"  {error_type}: {count}")
        
        if self.errors:
            print("\n最新のエラー（最大5件）:")
            for error in self.errors[-5:]:
                print(f"  {error[:200]}")
    
    def analyze_slow_queries(self):
        """スロークエリ分析"""
        print("\n" + "=" * 80)
        print("スロークエリ分析")
        print("=" * 80)
        
        if not self.slow_queries:
            print("\nスロークエリは検出されませんでした。")
            return
        
        print(f"\nスロークエリ数: {len(self.slow_queries)}")
        
        sorted_queries = sorted(self.slow_queries, key=lambda x: x['duration'], reverse=True)
        
        print("\n最も遅いクエリ（TOP 5）:")
        for i, query in enumerate(sorted_queries[:5], 1):
            print(f"\n{i}. 実行時間: {query['duration']:.2f} ms")
            print(f"   {query['line'][:300]}")
    
    def analyze_connections(self):
        """接続パターン分析"""
        print("\n" + "=" * 80)
        print("接続パターン分析")
        print("=" * 80)
        
        print("\nユーザー別接続数:")
        for user, count in sorted(self.connections.items(), key=lambda x: x[1], reverse=True):
            print(f"  {user}: {count}")
    
    def generate_report(self):
        """総合レポート生成"""
        print("\n" + "=" * 80)
        print("PostgreSQL ログ分析レポート")
        print(f"分析ファイル: {self.log_file}")
        print(f"分析日時: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        
        self.parse_log()
        self.analyze_errors()
        self.analyze_slow_queries()
        self.analyze_connections()
        
        # 推奨アクション
        print("\n" + "=" * 80)
        print("推奨アクション")
        print("=" * 80)
        
        if len(self.errors) > 100:
            print("⚠️  エラーが多発しています。アプリケーションまたはDB設定を確認してください。")
        
        if len(self.slow_queries) > 50:
            print("⚠️  スロークエリが多数検出されました。インデックス最適化を検討してください。")
        
        if max(self.connections.values(), default=0) > 1000:
            print("⚠️  特定ユーザーの接続数が多い。コネクションプーリングを確認してください。")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='PostgreSQL ログ分析ツール')
    parser.add_argument('log_file', help='分析対象のログファイル')
    args = parser.parse_args()
    
    analyzer = PostgreSQLLogAnalyzer(args.log_file)
    analyzer.generate_report()
