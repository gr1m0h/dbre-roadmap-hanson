-- PostgreSQL特化インデックス戦略
-- 使用方法: psql -f index_examples.sql

-- 1. 基本的なB-treeインデックス
CREATE INDEX idx_rooms_type ON rooms (room_type);
CREATE INDEX idx_rooms_price ON rooms (price_per_night);

-- 2. JSONB専用GINインデックス（含む検索用）
CREATE INDEX idx_rooms_amenities_gin ON rooms USING gin (amenities);

-- 3. 全文検索用GINインデックス
CREATE INDEX idx_guests_search_vector ON guests USING gin (search_vector);

-- 4. 配列専用GINインデックス
CREATE INDEX idx_rooms_tags_gin ON rooms USING gin (tags);

-- 5. GiSTインデックス（範囲型、期間検索用）
CREATE INDEX idx_reservations_stay_period ON room_reservations USING gist (stay_period);

-- 6. BRINインデックス（大規模テーブルの範囲検索用）
CREATE INDEX idx_reservations_created_at_brin ON room_reservations USING brin (created_at);

-- 7. 部分インデックス（アクティブな予約のみ）
CREATE INDEX idx_active_reservations 
ON room_reservations (room_id, stay_period) 
WHERE canceled_at IS NULL;

-- 8. 複合インデックス（カバリングインデックス）
CREATE INDEX idx_reservations_room_guest_period 
ON room_reservations (room_id, guest_id, stay_period);

-- 9. 式インデックス（計算カラム用）
CREATE INDEX idx_guests_fullname ON guests (lower(first_name || ' ' || last_name));

-- 10. JSONB式インデックス（特定フィールド高速化）
CREATE INDEX idx_rooms_amenities_wifi 
ON rooms ((amenities->>'wifi')) 
WHERE amenities->>'wifi' IS NOT NULL;
