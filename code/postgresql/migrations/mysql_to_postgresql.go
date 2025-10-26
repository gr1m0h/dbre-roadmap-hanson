package main

/*
MySQL → PostgreSQL マイグレーションツール

使用方法:
    go run mysql_to_postgresql.go
*/

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"

	_ "github.com/go-sql-driver/mysql"
	_ "github.com/lib/pq"
)

type Config struct {
	MySQLHost     string
	MySQLUser     string
	MySQLPassword string
	MySQLDatabase string
	PGHost        string
	PGUser        string
	PGPassword    string
	PGDatabase    string
}

func DefaultConfig() *Config {
	return &Config{
		MySQLHost:     "127.0.0.1",
		MySQLUser:     "training_user",
		MySQLPassword: "password",
		MySQLDatabase: "training_db",
		PGHost:        "127.0.0.1",
		PGUser:        "training_user",
		PGPassword:    "password",
		PGDatabase:    "training_db",
	}
}

func ConvertMySQLToPostgresDDL() map[string]string {
	return map[string]string{
		// データ型変換
		"AUTO_INCREMENT":            "SERIAL",
		"TINYINT(1)":                "BOOLEAN",
		"DATETIME":                  "TIMESTAMP WITH TIME ZONE",
		"JSON":                      "JSONB",
		"TEXT":                      "TEXT",
		// MySQL特有構文の削除
		"ENGINE=InnoDB":             "",
		"DEFAULT CHARSET=utf8mb4":   "",
		"COLLATE=utf8mb4_unicode_ci": "",
	}
}

func MigrateDataWithTransformation(config *Config) error {
	// MySQL接続
	mysqlDSN := fmt.Sprintf("%s:%s@tcp(%s)/%s",
		config.MySQLUser, config.MySQLPassword, config.MySQLHost, config.MySQLDatabase)
	mysqlDB, err := sql.Open("mysql", mysqlDSN)
	if err != nil {
		return fmt.Errorf("MySQL接続エラー: %w", err)
	}
	defer mysqlDB.Close()

	// PostgreSQL接続
	pgDSN := fmt.Sprintf("host=%s user=%s password=%s dbname=%s sslmode=disable",
		config.PGHost, config.PGUser, config.PGPassword, config.PGDatabase)
	pgDB, err := sql.Open("postgres", pgDSN)
	if err != nil {
		return fmt.Errorf("PostgreSQL接続エラー: %w", err)
	}
	defer pgDB.Close()

	// JSON列の変換（MySQL JSON → PostgreSQL JSONB）
	rows, err := mysqlDB.Query("SELECT id, metadata FROM room_reservations WHERE metadata IS NOT NULL")
	if err != nil {
		return fmt.Errorf("MySQLクエリエラー: %w", err)
	}
	defer rows.Close()

	tx, err := pgDB.Begin()
	if err != nil {
		return fmt.Errorf("トランザクション開始エラー: %w", err)
	}

	for rows.Next() {
		var id int
		var metadata string

		if err := rows.Scan(&id, &metadata); err != nil {
			tx.Rollback()
			return fmt.Errorf("行スキャンエラー: %w", err)
		}

		// MySQL JSONをGoのmapに変換後、PostgreSQL JSONBに
		var jsonData map[string]interface{}
		if err := json.Unmarshal([]byte(metadata), &jsonData); err != nil {
			log.Printf("警告: JSON変換エラー (id=%d): %v", id, err)
			continue
		}

		jsonBytes, err := json.Marshal(jsonData)
		if err != nil {
			tx.Rollback()
			return fmt.Errorf("JSONマーシャルエラー: %w", err)
		}

		_, err = tx.Exec(
			"UPDATE room_reservations SET metadata = $1 WHERE id = $2",
			string(jsonBytes), id,
		)
		if err != nil {
			tx.Rollback()
			return fmt.Errorf("PostgreSQL更新エラー: %w", err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("コミットエラー: %w", err)
	}

	log.Println("JSON data migration completed")
	return nil
}

func main() {
	config := DefaultConfig()

	if err := MigrateDataWithTransformation(config); err != nil {
		log.Fatalf("マイグレーションエラー: %v", err)
	}

	log.Println("マイグレーション完了")
}
