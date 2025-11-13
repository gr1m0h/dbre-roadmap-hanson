-- PostgreSQL Training Schema from postgresql.md
-- This script creates the hotel booking system schema

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pg_buffercache";
CREATE EXTENSION IF NOT EXISTS "pgstattuple";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create custom types
CREATE TYPE room_type_enum AS ENUM ('single', 'double', 'suite', 'penthouse');
CREATE TYPE guest_status_enum AS ENUM ('active', 'inactive', 'blocked');

-- Drop existing tables if they exist
DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS room_reservations CASCADE;
DROP TABLE IF EXISTS guests CASCADE;
DROP TABLE IF EXISTS rooms CASCADE;

-- Create rooms table with JSONB and array columns
CREATE TABLE rooms (
    id SERIAL PRIMARY KEY,
    room_number VARCHAR(10) UNIQUE NOT NULL,
    room_type room_type_enum NOT NULL,
    floor_number INTEGER NOT NULL,
    price_per_night DECIMAL(10, 2) NOT NULL,
    amenities JSONB DEFAULT '[]'::JSONB,
    tags TEXT[] DEFAULT ARRAY[]::TEXT[],
    is_available BOOLEAN DEFAULT true,
    last_cleaned TIMESTAMP,
    metadata JSONB DEFAULT '{}'::JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create guests table with full-text search
CREATE TABLE guests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    guest_type guest_status_enum DEFAULT 'active',
    preferences TEXT[] DEFAULT ARRAY[]::TEXT[],
    profile JSONB DEFAULT '{}'::JSONB,
    registration_date DATE DEFAULT CURRENT_DATE,
    search_vector tsvector,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create room_reservations table with range types and exclusion constraint
CREATE TABLE room_reservations (
    id BIGSERIAL PRIMARY KEY,
    room_id INTEGER REFERENCES rooms(id) ON DELETE CASCADE,
    guest_id UUID REFERENCES guests(id) ON DELETE CASCADE,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    stay_period daterange GENERATED ALWAYS AS (daterange(check_in, check_out, '[]')) STORED,
    total_price DECIMAL(10, 2) NOT NULL,
    is_paid BOOLEAN DEFAULT false,
    metadata JSONB DEFAULT '{}'::JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    EXCLUDE USING gist (room_id WITH =, stay_period WITH &&) -- Prevent double bookings
);

-- Create reviews table
CREATE TABLE reviews (
    id SERIAL PRIMARY KEY,
    reservation_id BIGINT REFERENCES room_reservations(id) ON DELETE CASCADE,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    comment_vector tsvector,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create all indexes from postgresql.md
-- B-tree indexes
CREATE INDEX idx_rooms_type ON rooms (room_type);
CREATE INDEX idx_guests_email ON guests (email);

-- JSONB GIN indexes
CREATE INDEX idx_rooms_amenities ON rooms USING gin (amenities);
CREATE INDEX idx_guests_profile ON guests USING gin (profile);
CREATE INDEX idx_guest_loyalty ON guests USING btree ((profile->>'loyalty_level'));

-- Array GIN indexes
CREATE INDEX idx_rooms_tags ON rooms USING gin (tags);
CREATE INDEX idx_guests_preferences ON guests USING gin (preferences);

-- Full-text search GIN indexes
CREATE INDEX idx_guests_search ON guests USING gin (search_vector);
CREATE INDEX idx_reviews_search ON reviews USING gin (comment_vector);

-- Range type GiST index
CREATE INDEX idx_reservations_period ON room_reservations USING gist (stay_period);

-- Composite indexes
CREATE INDEX idx_reservations_room_created ON room_reservations (room_id, created_at);

-- Partial indexes
CREATE INDEX idx_unpaid_reservations ON room_reservations (guest_id, created_at) WHERE is_paid = false;
CREATE INDEX idx_active_guests ON guests (email, registration_date) WHERE guest_type = 'active';

-- Function indexes
CREATE INDEX idx_guest_fullname ON guests (lower(first_name || ' ' || last_name));

-- BRIN index for large tables
CREATE INDEX idx_reservations_created_brin ON room_reservations USING brin (created_at);

-- Create trigger functions
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE OR REPLACE FUNCTION update_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := to_tsvector('english',
        COALESCE(NEW.first_name, '') || ' ' ||
        COALESCE(NEW.last_name, '') || ' ' ||
        COALESCE(NEW.email, '')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_review_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.comment_vector := to_tsvector('english', COALESCE(NEW.comment, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers
CREATE TRIGGER update_rooms_updated_at
    BEFORE UPDATE ON rooms
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_guests_updated_at
    BEFORE UPDATE ON guests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_reservations_updated_at
    BEFORE UPDATE ON room_reservations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_guest_search_vector
    BEFORE INSERT OR UPDATE ON guests
    FOR EACH ROW EXECUTE FUNCTION update_search_vector();

CREATE TRIGGER update_review_vector
    BEFORE INSERT OR UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_review_vector();

-- Insert sample data
INSERT INTO rooms (room_number, room_type, floor_number, price_per_night, amenities, tags) VALUES
    ('101', 'single', 1, 10000, '{"wifi": true, "tv": true, "minibar": false}'::JSONB, ARRAY['quiet', 'city-view']),
    ('102', 'double', 1, 15000, '{"wifi": true, "tv": true, "minibar": true}'::JSONB, ARRAY['spacious', 'city-view']),
    ('201', 'suite', 2, 25000, '{"wifi": true, "tv": true, "minibar": true, "jacuzzi": true}'::JSONB, ARRAY['luxury', 'ocean-view']),
    ('301', 'penthouse', 3, 50000, '{"wifi": true, "tv": true, "minibar": true, "jacuzzi": true, "kitchen": true}'::JSONB, ARRAY['luxury', 'ocean-view', 'private-terrace']);

INSERT INTO guests (email, first_name, last_name, phone, preferences, profile) VALUES
    ('john.doe@example.com', 'John', 'Doe', '123-456-7890', ARRAY['non-smoking', 'high-floor'], '{"loyalty_level": "gold", "total_stays": 15}'::JSONB),
    ('jane.smith@example.com', 'Jane', 'Smith', '098-765-4321', ARRAY['quiet-room', 'early-checkin'], '{"loyalty_level": "silver", "total_stays": 8}'::JSONB);

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;

-- Analyze tables for query planner
ANALYZE;