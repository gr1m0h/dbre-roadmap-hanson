package main

/*
MongoDB → PostgreSQL マイグレーションツール

使用方法:
    go run mongodb_to_postgresql.go
*/

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"time"

	_ "github.com/lib/pq"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type PostgresConfig struct {
	Host     string
	User     string
	Password string
	Database string
}

func DefaultPostgresConfig() *PostgresConfig {
	return &PostgresConfig{
		Host:     "localhost",
		User:     "postgres",
		Password: "password",
		Database: "target_db",
	}
}

func MigrateMongoDBDocuments() error {
	ctx := context.Background()

	// MongoDB接続
	mongoClient, err := mongo.Connect(ctx, options.Client().ApplyURI("mongodb://localhost:27017/"))
	if err != nil {
		return fmt.Errorf("MongoDB接続エラー: %w", err)
	}
	defer mongoClient.Disconnect(ctx)

	mongoDB := mongoClient.Database("hotel_booking")

	// PostgreSQL接続
	pgConfig := DefaultPostgresConfig()
	pgDSN := fmt.Sprintf("host=%s user=%s password=%s dbname=%s sslmode=disable",
		pgConfig.Host, pgConfig.User, pgConfig.Password, pgConfig.Database)
	pgDB, err := sql.Open("postgres", pgDSN)
	if err != nil {
		return fmt.Errorf("PostgreSQL接続エラー: %w", err)
	}
	defer pgDB.Close()

	// テーブル作成
	_, err = pgDB.Exec(`
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
	`)
	if err != nil {
		return fmt.Errorf("テーブル作成エラー: %w", err)
	}

	// MongoDBコレクションを順次移行
	collections, err := mongoDB.ListCollectionNames(ctx, bson.D{})
	if err != nil {
		return fmt.Errorf("コレクション一覧取得エラー: %w", err)
	}

	for _, collectionName := range collections {
		collection := mongoDB.Collection(collectionName)
		log.Printf("Migrating collection: %s", collectionName)

		cursor, err := collection.Find(ctx, bson.D{})
		if err != nil {
			return fmt.Errorf("検索エラー (%s): %w", collectionName, err)
		}

		batchSize := 1000
		count := 0

		tx, err := pgDB.Begin()
		if err != nil {
			return fmt.Errorf("トランザクション開始エラー: %w", err)
		}

		for cursor.Next(ctx) {
			var doc bson.M
			if err := cursor.Decode(&doc); err != nil {
				log.Printf("警告: ドキュメントデコードエラー: %v", err)
				continue
			}

			// _idを取り出して文字列に変換
			docID := fmt.Sprintf("%v", doc["_id"])
			delete(doc, "_id")

			// BSONをJSONに変換
			jsonData, err := json.Marshal(doc)
			if err != nil {
				log.Printf("警告: JSONマーシャルエラー: %v", err)
				continue
			}

			_, err = tx.Exec(`
				INSERT INTO document_store (collection_name, document_id, document_data)
				VALUES ($1, $2, $3)
				ON CONFLICT (collection_name, document_id)
				DO UPDATE SET document_data = EXCLUDED.document_data
			`, collectionName, docID, string(jsonData))
			if err != nil {
				tx.Rollback()
				return fmt.Errorf("挿入エラー: %w", err)
			}

			count++
			if count%batchSize == 0 {
				if err := tx.Commit(); err != nil {
					return fmt.Errorf("コミットエラー: %w", err)
				}
				log.Printf("  Migrated %d documents", count)

				// 新しいトランザクション開始
				tx, err = pgDB.Begin()
				if err != nil {
					return fmt.Errorf("トランザクション開始エラー: %w", err)
				}
			}
		}

		// 残りをコミット
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("コミットエラー: %w", err)
		}

		cursor.Close(ctx)
		log.Printf("Completed: %s (total: %d documents)", collectionName, count)
	}

	log.Println("Migration completed successfully")
	return nil
}

func main() {
	if err := MigrateMongoDBDocuments(); err != nil {
		log.Fatalf("マイグレーションエラー: %v", err)
	}
}
