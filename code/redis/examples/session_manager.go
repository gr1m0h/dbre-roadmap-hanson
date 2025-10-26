package main

/*
Redis セッション管理システム

使用方法:
    manager := NewRedisSessionManager("localhost:6379", 3600)
    sessionID, _ := manager.CreateSession(1001, map[string]interface{}{"theme": "dark"})
    sessionData, _ := manager.GetSession(sessionID)
*/

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/google/uuid"
)

var ctx = context.Background()

type RedisSessionManager struct {
	client     *redis.Client
	defaultTTL time.Duration
}

func NewRedisSessionManager(addr string, ttlSeconds int) *RedisSessionManager {
	client := redis.NewClient(&redis.Options{
		Addr: addr,
	})

	return &RedisSessionManager{
		client:     client,
		defaultTTL: time.Duration(ttlSeconds) * time.Second,
	}
}

func (m *RedisSessionManager) CreateSession(userID int, userData map[string]interface{}) (string, error) {
	sessionID := uuid.New().String()
	sessionKey := fmt.Sprintf("session:%s", sessionID)

	// セッションデータ構築
	now := time.Now().Format(time.RFC3339)
	userDataJSON, err := json.Marshal(userData)
	if err != nil {
		return "", err
	}

	sessionData := map[string]interface{}{
		"user_id":       userID,
		"created_at":    now,
		"last_accessed": now,
		"data":          string(userDataJSON),
	}

	// セッションデータ保存（Hash使用）
	if err := m.client.HSet(ctx, sessionKey, sessionData).Err(); err != nil {
		return "", err
	}

	// TTL設定
	if err := m.client.Expire(ctx, sessionKey, m.defaultTTL).Err(); err != nil {
		return "", err
	}

	// ユーザーのアクティブセッション管理（Set使用）
	userSessionsKey := fmt.Sprintf("user_sessions:%d", userID)
	if err := m.client.SAdd(ctx, userSessionsKey, sessionID).Err(); err != nil {
		return "", err
	}
	if err := m.client.Expire(ctx, userSessionsKey, m.defaultTTL).Err(); err != nil {
		return "", err
	}

	return sessionID, nil
}

func (m *RedisSessionManager) GetSession(sessionID string) (map[string]string, error) {
	sessionKey := fmt.Sprintf("session:%s", sessionID)
	sessionData, err := m.client.HGetAll(ctx, sessionKey).Result()
	if err != nil {
		return nil, err
	}

	if len(sessionData) == 0 {
		return nil, nil
	}

	// 最終アクセス時刻更新
	now := time.Now().Format(time.RFC3339)
	if err := m.client.HSet(ctx, sessionKey, "last_accessed", now).Err(); err != nil {
		return nil, err
	}
	if err := m.client.Expire(ctx, sessionKey, m.defaultTTL).Err(); err != nil {
		return nil, err
	}

	return sessionData, nil
}

func (m *RedisSessionManager) UpdateSession(sessionID string, data map[string]interface{}) error {
	sessionKey := fmt.Sprintf("session:%s", sessionID)
	dataJSON, err := json.Marshal(data)
	if err != nil {
		return err
	}

	if err := m.client.HSet(ctx, sessionKey, "data", string(dataJSON)).Err(); err != nil {
		return err
	}
	return m.client.Expire(ctx, sessionKey, m.defaultTTL).Err()
}

func (m *RedisSessionManager) DestroySession(sessionID string) error {
	sessionKey := fmt.Sprintf("session:%s", sessionID)

	// セッションデータ取得
	sessionData, err := m.client.HGetAll(ctx, sessionKey).Result()
	if err != nil {
		return err
	}

	// ユーザーセッションリストから削除
	if userID, ok := sessionData["user_id"]; ok {
		userSessionsKey := fmt.Sprintf("user_sessions:%s", userID)
		m.client.SRem(ctx, userSessionsKey, sessionID)
	}

	// セッション削除
	return m.client.Del(ctx, sessionKey).Err()
}

func (m *RedisSessionManager) GetActiveSessionsCount() (int64, error) {
	pattern := "session:*"
	keys, err := m.client.Keys(ctx, pattern).Result()
	if err != nil {
		return 0, err
	}
	return int64(len(keys)), nil
}

func main() {
	manager := NewRedisSessionManager("localhost:6379", 3600)

	// セッション作成
	userData := map[string]interface{}{
		"theme":    "dark",
		"language": "ja",
	}
	sessionID, err := manager.CreateSession(1001, userData)
	if err != nil {
		log.Fatalf("セッション作成エラー: %v", err)
	}
	fmt.Printf("Created session: %s\n", sessionID)

	// セッション取得
	sessionData, err := manager.GetSession(sessionID)
	if err != nil {
		log.Fatalf("セッション取得エラー: %v", err)
	}
	fmt.Printf("Session data: %v\n", sessionData)

	// アクティブセッション数
	count, err := manager.GetActiveSessionsCount()
	if err != nil {
		log.Fatalf("セッション数取得エラー: %v", err)
	}
	fmt.Printf("Active sessions: %d\n", count)
}
