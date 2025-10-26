package main

/*
Redis Sentinel 管理システム

使用方法:
    sentinelHosts := []string{
        "sentinel1.example.com:26379",
        "sentinel2.example.com:26379",
        "sentinel3.example.com:26379",
    }
    manager := NewRedisSentinelManager(sentinelHosts, "mymaster")
    master := manager.GetMaster()
*/

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/go-redis/redis/v8"
)

var ctx = context.Background()

type RedisSentinelManager struct {
	sentinelClient *redis.Client
	serviceName    string
	masterClient   *redis.Client
	slaveClient    *redis.Client
}

func NewRedisSentinelManager(sentinelAddrs []string, serviceName string) *RedisSentinelManager {
	if serviceName == "" {
		serviceName = "mymaster"
	}

	sentinelClient := redis.NewFailoverClient(&redis.FailoverOptions{
		MasterName:    serviceName,
		SentinelAddrs: sentinelAddrs,
	})

	return &RedisSentinelManager{
		sentinelClient: sentinelClient,
		serviceName:    serviceName,
	}
}

func (m *RedisSentinelManager) GetMaster() *redis.Client {
	if m.masterClient == nil {
		m.masterClient = m.sentinelClient
	}
	return m.masterClient
}

func (m *RedisSentinelManager) GetSlave() *redis.Client {
	// 読み取り専用のスレーブ接続を取得
	// Note: go-redis/v8では、FailoverClientが自動的にマスター/スレーブを管理
	if m.slaveClient == nil {
		m.slaveClient = m.sentinelClient
	}
	return m.slaveClient
}

func (m *RedisSentinelManager) GetMasterInfo() (map[string]string, error) {
	result, err := m.sentinelClient.Info(ctx, "replication").Result()
	if err != nil {
		log.Printf("Master discovery failed: %v", err)
		return nil, err
	}

	info := make(map[string]string)
	info["replication_info"] = result
	return info, nil
}

func (m *RedisSentinelManager) WaitForMaster(timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		if _, err := m.GetMasterInfo(); err == nil {
			log.Println("Master available")
			return true
		}
		time.Sleep(1 * time.Second)
	}

	log.Println("Master not available within timeout")
	return false
}

func WriteData(manager *RedisSentinelManager, key, value string) error {
	master := manager.GetMaster()
	return master.Set(ctx, key, value, 0).Err()
}

func ReadData(manager *RedisSentinelManager, key string) (string, error) {
	// 読み取りはスレーブから
	slave := manager.GetSlave()
	val, err := slave.Get(ctx, key).Result()
	if err == nil {
		return val, nil
	}

	// スレーブが利用できない場合はマスターから
	master := manager.GetMaster()
	return master.Get(ctx, key).Result()
}

func main() {
	sentinelHosts := []string{
		"sentinel1.example.com:26379",
		"sentinel2.example.com:26379",
		"sentinel3.example.com:26379",
	}

	manager := NewRedisSentinelManager(sentinelHosts, "mymaster")

	// 書き込み
	if err := WriteData(manager, "test_key", "test_value"); err != nil {
		log.Printf("書き込みエラー: %v", err)
	} else {
		fmt.Println("データ書き込み成功")
	}

	// 読み取り
	value, err := ReadData(manager, "test_key")
	if err != nil {
		log.Printf("読み取りエラー: %v", err)
	} else {
		fmt.Printf("読み取り値: %s\n", value)
	}

	// マスター情報取得
	info, err := manager.GetMasterInfo()
	if err != nil {
		log.Printf("マスター情報取得エラー: %v", err)
	} else {
		fmt.Printf("マスター情報: %v\n", info)
	}
}
