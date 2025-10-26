#!/usr/bin/env python3
"""
MongoDB → PostgreSQL マイグレーションツール

使用方法:
    python mongodb_to_postgresql.py
"""

from pymongo import MongoClient
import psycopg2
import json
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POSTGRES_CONFIG = {
    'host': 'localhost',
    'database': 'target_db',
    'user': 'postgres',
    'password': 'password'
}

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
        
        logger.info(f"Migrating collection: {collection_name}")
        batch_size = 1000
        batch = []

        for doc in collection.find():
            doc_id = str(doc.pop('_id'))

            postgres_cursor.execute("""
                INSERT INTO document_store (collection_name, document_id, document_data)
                VALUES (%s, %s, %s)
                ON CONFLICT (collection_name, document_id)
                DO UPDATE SET document_data = EXCLUDED.document_data
            """, (collection_name, doc_id, json.dumps(doc, default=str)))
            
            if len(batch) >= batch_size:
                postgres_conn.commit()
                batch = []
                logger.info(f"  Migrated {batch_size} documents")

        postgres_conn.commit()
        logger.info(f"Completed: {collection_name}")

    postgres_conn.close()
    mongo_client.close()
    logger.info("Migration completed successfully")

if __name__ == "__main__":
    migrate_mongodb_documents()
