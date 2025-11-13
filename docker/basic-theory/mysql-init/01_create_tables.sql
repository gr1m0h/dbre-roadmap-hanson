-- Basic Theory MySQL Initialization Script
-- This script demonstrates concepts from basic_theory.md

-- Use the database
USE basic_theory_db;

-- Drop existing tables if they exist
DROP TABLE IF EXISTS test_lock;
DROP TABLE IF EXISTS test_index;
DROP TABLE IF EXISTS performance_test;
DROP TABLE IF EXISTS test_storage_engine;

-- Create test table for lock demonstration
CREATE TABLE test_lock (
    id INT AUTO_INCREMENT PRIMARY KEY,
    balance DECIMAL(10,2),
    last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Create test table for index demonstration
CREATE TABLE test_index (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255),
    name VARCHAR(255),
    age INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_email (email),
    KEY idx_age (age),
    KEY idx_age_created (age, created_at)
) ENGINE=InnoDB;

-- Create performance test table from basic_theory.md
CREATE TABLE performance_test (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255),
    age INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data TEXT
) ENGINE=InnoDB;

-- Create table to demonstrate storage engines
CREATE TABLE test_storage_engine (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255)
) ENGINE=MyISAM;

-- Insert sample data for lock test
INSERT INTO test_lock (balance) VALUES 
    (1000.00),
    (2000.00),
    (3000.00);

-- Generate test data using stored procedure
DELIMITER //
CREATE PROCEDURE GenerateTestData()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 10000 DO
        INSERT INTO test_index (email, name, age) VALUES 
            (CONCAT('user', i, '@example.com'),
             CONCAT('User ', i),
             20 + (i % 60));
        SET i = i + 1;
        -- Commit every 1000 rows
        IF i % 1000 = 0 THEN
            COMMIT;
        END IF;
    END WHILE;
END //
DELIMITER ;

-- Call procedure to generate data
CALL GenerateTestData();

-- Grant permissions
GRANT ALL PRIVILEGES ON basic_theory_db.* TO 'mysql_user'@'%';
FLUSH PRIVILEGES;

-- Update statistics
ANALYZE TABLE test_index;
ANALYZE TABLE performance_test;