-- Basic Theory PostgreSQL Initialization Script
-- This script demonstrates concepts from basic_theory.md

-- Drop existing tables if they exist
DROP TABLE IF EXISTS test_deadlock CASCADE;
DROP TABLE IF EXISTS test_vacuum CASCADE;
DROP TABLE IF EXISTS test_index CASCADE;
DROP TABLE IF EXISTS performance_test CASCADE;

-- Create test table for MVCC demonstration
CREATE TABLE test_vacuum (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create test table for index demonstration
CREATE TABLE test_index (
    id BIGINT PRIMARY KEY,
    email VARCHAR(255),
    name VARCHAR(255),
    age INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create test table for deadlock demonstration
CREATE TABLE test_deadlock (
    id INTEGER PRIMARY KEY,
    balance DECIMAL(10,2),
    last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create performance test table from basic_theory.md
CREATE TABLE performance_test (
    id BIGINT PRIMARY KEY,
    email VARCHAR(255),
    age INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data TEXT
);

-- Insert sample data for MVCC test
INSERT INTO test_vacuum (data) VALUES 
    ('Record 1 - for MVCC testing'),
    ('Record 2 - for MVCC testing'),
    ('Record 3 - for MVCC testing');

-- Insert sample data for deadlock test
INSERT INTO test_deadlock (id, balance) VALUES 
    (1, 1000.00),
    (2, 2000.00),
    (3, 3000.00);

-- Generate test data for index demo (10,000 rows)
INSERT INTO test_index (id, email, name, age)
SELECT 
    generate_series(1, 10000),
    'user' || generate_series(1, 10000) || '@example.com',
    'User ' || generate_series(1, 10000),
    20 + (generate_series(1, 10000) % 60);

-- Create indexes for testing
CREATE INDEX idx_email ON test_index(email);
CREATE INDEX idx_age ON test_index(age);
CREATE INDEX idx_age_created ON test_index(age, created_at);

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;

-- Create extension for monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Analyze tables for query planner
ANALYZE;