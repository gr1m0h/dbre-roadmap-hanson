-- MySQL Training Schema from mysql.md
-- Hotel booking system schema for MySQL

USE training_db;

-- Drop existing tables if they exist
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS room_reservations;
DROP TABLE IF EXISTS guests;
DROP TABLE IF EXISTS rooms;

-- Create rooms table
CREATE TABLE rooms (
    id INT AUTO_INCREMENT PRIMARY KEY,
    room_number VARCHAR(10) UNIQUE NOT NULL,
    room_type ENUM('single', 'double', 'suite', 'penthouse') NOT NULL,
    floor_number INT NOT NULL,
    price_per_night DECIMAL(10, 2) NOT NULL,
    amenities JSON DEFAULT NULL,
    is_available BOOLEAN DEFAULT TRUE,
    last_cleaned TIMESTAMP NULL,
    metadata JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_room_type (room_type),
    INDEX idx_price (price_per_night),
    INDEX idx_floor (floor_number),
    INDEX idx_available_type (is_available, room_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create guests table
CREATE TABLE guests (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    guest_status ENUM('active', 'inactive', 'blocked') DEFAULT 'active',
    preferences JSON DEFAULT NULL,
    profile JSON DEFAULT NULL,
    registration_date DATE DEFAULT (CURRENT_DATE),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_name (last_name, first_name),
    INDEX idx_status (guest_status),
    FULLTEXT idx_fulltext_name (first_name, last_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create room_reservations table
CREATE TABLE room_reservations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    room_id INT NOT NULL,
    guest_id CHAR(36) NOT NULL,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    total_price DECIMAL(10, 2) NOT NULL,
    is_paid BOOLEAN DEFAULT FALSE,
    payment_date TIMESTAMP NULL,
    special_requests TEXT,
    metadata JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE RESTRICT,
    FOREIGN KEY (guest_id) REFERENCES guests(id) ON DELETE RESTRICT,
    INDEX idx_room_dates (room_id, check_in, check_out),
    INDEX idx_guest_dates (guest_id, check_in),
    INDEX idx_unpaid (is_paid, created_at),
    INDEX idx_check_in (check_in),
    INDEX idx_check_out (check_out),
    -- Prevent double bookings using unique constraint
    UNIQUE KEY unique_room_booking (room_id, check_in, check_out)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create reviews table
CREATE TABLE reviews (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reservation_id BIGINT NOT NULL,
    rating TINYINT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reservation_id) REFERENCES room_reservations(id) ON DELETE CASCADE,
    INDEX idx_rating (rating),
    INDEX idx_reservation (reservation_id),
    FULLTEXT idx_comment (comment)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create table to demonstrate different storage engines
CREATE TABLE log_entries (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    log_level VARCHAR(10),
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_created (created_at),
    INDEX idx_level (log_level)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create a memory table for caching
CREATE TABLE cache_entries (
    cache_key VARCHAR(255) PRIMARY KEY,
    cache_value TEXT,
    expires_at TIMESTAMP
) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert sample data
INSERT INTO rooms (room_number, room_type, floor_number, price_per_night, amenities) VALUES
    ('101', 'single', 1, 10000.00, '{"wifi": true, "tv": true, "minibar": false}'),
    ('102', 'double', 1, 15000.00, '{"wifi": true, "tv": true, "minibar": true}'),
    ('201', 'suite', 2, 25000.00, '{"wifi": true, "tv": true, "minibar": true, "jacuzzi": true}'),
    ('301', 'penthouse', 3, 50000.00, '{"wifi": true, "tv": true, "minibar": true, "jacuzzi": true, "kitchen": true}'),
    ('103', 'single', 1, 10000.00, '{"wifi": true, "tv": true, "minibar": false}'),
    ('104', 'double', 1, 15000.00, '{"wifi": true, "tv": true, "minibar": true}'),
    ('202', 'suite', 2, 25000.00, '{"wifi": true, "tv": true, "minibar": true, "jacuzzi": false}'),
    ('203', 'double', 2, 18000.00, '{"wifi": true, "tv": true, "minibar": true, "balcony": true}');

INSERT INTO guests (email, first_name, last_name, phone, preferences, profile) VALUES
    ('john.doe@example.com', 'John', 'Doe', '123-456-7890', '["non-smoking", "high-floor"]', '{"loyalty_level": "gold", "total_stays": 15}'),
    ('jane.smith@example.com', 'Jane', 'Smith', '098-765-4321', '["quiet-room", "early-checkin"]', '{"loyalty_level": "silver", "total_stays": 8}'),
    ('alice.johnson@example.com', 'Alice', 'Johnson', '555-123-4567', '["pet-friendly", "late-checkout"]', '{"loyalty_level": "bronze", "total_stays": 3}'),
    ('bob.wilson@example.com', 'Bob', 'Wilson', '555-987-6543', '["gym-access", "business-center"]', '{"loyalty_level": "platinum", "total_stays": 25}');

-- Create stored procedure for generating test data
DELIMITER //
CREATE PROCEDURE GenerateReservations(IN num_reservations INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE room_count INT;
    DECLARE guest_count INT;
    DECLARE random_room INT;
    DECLARE random_guest INT;
    DECLARE random_checkin DATE;
    DECLARE random_nights INT;
    
    SELECT COUNT(*) INTO room_count FROM rooms;
    SELECT COUNT(*) INTO guest_count FROM guests;
    
    WHILE i < num_reservations DO
        SET random_room = FLOOR(1 + RAND() * room_count);
        SET random_guest = FLOOR(1 + RAND() * guest_count);
        SET random_checkin = DATE_ADD(CURRENT_DATE, INTERVAL FLOOR(RAND() * 365) DAY);
        SET random_nights = FLOOR(1 + RAND() * 7);
        
        INSERT IGNORE INTO room_reservations (room_id, guest_id, check_in, check_out, total_price, is_paid)
        SELECT 
            r.id,
            g.id,
            random_checkin,
            DATE_ADD(random_checkin, INTERVAL random_nights DAY),
            r.price_per_night * random_nights,
            RAND() > 0.2
        FROM rooms r, guests g
        WHERE r.id = random_room AND g.id = (SELECT id FROM guests LIMIT random_guest, 1);
        
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

-- Generate sample reservations
CALL GenerateReservations(20);

-- Create views for reporting
CREATE VIEW v_room_occupancy AS
SELECT 
    r.room_number,
    r.room_type,
    COUNT(res.id) as total_bookings,
    COALESCE(SUM(res.total_price), 0) as total_revenue,
    COALESCE(AVG(res.total_price), 0) as avg_price
FROM rooms r
LEFT JOIN room_reservations res ON r.id = res.room_id
GROUP BY r.id, r.room_number, r.room_type;

CREATE VIEW v_guest_statistics AS
SELECT 
    g.email,
    CONCAT(g.first_name, ' ', g.last_name) as full_name,
    g.guest_status,
    COUNT(res.id) as total_reservations,
    COALESCE(SUM(res.total_price), 0) as total_spent,
    COALESCE(AVG(res.total_price), 0) as avg_spent
FROM guests g
LEFT JOIN room_reservations res ON g.id = res.guest_id
GROUP BY g.id;

-- Grant permissions
GRANT ALL PRIVILEGES ON training_db.* TO 'mysql_user'@'%';
FLUSH PRIVILEGES;

-- Update table statistics
ANALYZE TABLE rooms;
ANALYZE TABLE guests;
ANALYZE TABLE room_reservations;
ANALYZE TABLE reviews;