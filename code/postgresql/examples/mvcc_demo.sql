-- PostgreSQL MVCC デモンストレーション
-- 使用方法: psql -f mvcc_demo.sql

-- トランザクション分離レベルの確認
SHOW transaction_isolation;

-- デモ用テーブル作成
CREATE TABLE IF NOT EXISTS rooms (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    price_per_night DECIMAL(10, 2)
);

INSERT INTO rooms (name, price_per_night) VALUES ('Room 101', 10000);

-- セッション1のシミュレーション（別ターミナルで実行）
-- BEGIN;
-- UPDATE rooms SET price_per_night = 15000 WHERE id = 1;
-- SELECT txid_current();  -- 現在のトランザクションID

-- セッション2のシミュレーション（別ターミナルで実行）
-- SELECT price_per_night FROM rooms WHERE id = 1;  -- 古い値が見える
-- SELECT txid_current_snapshot();  -- 見えるトランザクションの範囲

-- システムカラムの確認
SELECT xmin, xmax, ctid, * FROM rooms WHERE id = 1;

-- VACUUM関連統計
SELECT
    schemaname,
    tablename,
    n_live_tup,
    n_dead_tup,
    ROUND(n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_ratio,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
WHERE tablename = 'rooms'
ORDER BY dead_ratio DESC NULLS LAST;
