-- Additive production schema for the Railway MySQL service.
-- This file intentionally contains no DROP statements.

CREATE TABLE IF NOT EXISTS zone (
  ZoneNo INT NOT NULL PRIMARY KEY,
  ZoneName VARCHAR(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO zone (ZoneNo, ZoneName) VALUES
  (1, 'Zone 1'), (2, 'Zone 2'), (3, 'Zone 3'), (4, 'Zone 4'),
  (5, 'Zone 5'), (6, 'Zone 6'), (7, 'Zone 7'), (8, 'Zone 8'),
  (9, 'Zone 9'), (10, 'Zone 10'), (11, 'Zone 11'), (12, 'Zone 12'),
  (13, 'Zone 13'), (14, 'Zone 14'), (15, 'Zone 15'), (16, 'Zone 16'),
  (17, 'Zone 17'), (18, 'Zone 18'), (19, 'Zone 19'), (20, 'Zone 20'),
  (21, 'Zone 21'), (22, 'Zone 22'), (23, 'Zone 23'), (24, 'Zone 24'),
  (25, 'Zone 25'), (26, 'Zone 26'), (27, 'Zone 27'), (28, 'Zone 28')
ON DUPLICATE KEY UPDATE ZoneName = VALUES(ZoneName);

CREATE TABLE IF NOT EXISTS farmer (
  FarmerID INT NOT NULL AUTO_INCREMENT,
  Email VARCHAR(100) NOT NULL,
  Password VARCHAR(255) NOT NULL COMMENT 'Store Hashed Password',
  F_Name VARCHAR(100) NOT NULL,
  L_Name VARCHAR(100) NOT NULL,
  FailedAttempts INT NOT NULL DEFAULT 0,
  LockedUntil DATETIME NULL,
  PRIMARY KEY (FarmerID),
  UNIQUE KEY uq_farmer_email (Email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS field_profile (
  FieldID INT NOT NULL AUTO_INCREMENT,
  FarmerID INT NOT NULL,
  ZoneNo INT NOT NULL,
  Size DECIMAL(10,2) NULL,
  PRIMARY KEY (FieldID),
  INDEX idx_field_farmer (FarmerID),
  INDEX idx_field_zone (ZoneNo),
  CONSTRAINT fk_field_farmer FOREIGN KEY (FarmerID) REFERENCES farmer (FarmerID),
  CONSTRAINT fk_field_zone FOREIGN KEY (ZoneNo) REFERENCES zone (ZoneNo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS irrigation_request (
  RequestID INT NOT NULL AUTO_INCREMENT,
  FarmerID INT NOT NULL,
  FieldID INT NOT NULL,
  RequestTime DATETIME NOT NULL,
  Status VARCHAR(20) NOT NULL DEFAULT 'Pending',
  PRIMARY KEY (RequestID),
  INDEX idx_request_farmer (FarmerID),
  INDEX idx_request_field (FieldID),
  CONSTRAINT fk_request_farmer FOREIGN KEY (FarmerID) REFERENCES farmer (FarmerID),
  CONSTRAINT fk_request_field FOREIGN KEY (FieldID) REFERENCES field_profile (FieldID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS users (
  UserID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  AccountID INT NULL,
  Username VARCHAR(100) NOT NULL,
  Email VARCHAR(255) NULL,
  PasswordHash VARCHAR(255) NOT NULL,
  FirstName VARCHAR(100) NOT NULL DEFAULT '',
  LastName VARCHAR(100) NOT NULL DEFAULT '',
  Role ENUM('admin', 'officer', 'farmer') NOT NULL DEFAULT 'farmer',
  CreatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UpdatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (UserID),
  UNIQUE KEY uq_users_username (Username),
  UNIQUE KEY uq_users_email (Email),
  INDEX idx_users_role (Role),
  INDEX idx_users_account (Role, AccountID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS request_sensor_snapshots (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  RequestID INT NOT NULL,
  FarmerID INT NOT NULL,
  FieldID INT NOT NULL,
  ZoneNo INT NOT NULL,
  device_id VARCHAR(80) NOT NULL,
  moisture DECIMAL(5,2) NOT NULL,
  temperature DECIMAL(6,2) NOT NULL,
  recorded_at DATETIME(6) NOT NULL,
  captured_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_request_snapshot (RequestID, FarmerID, FieldID),
  INDEX idx_request_snapshot_lookup (FarmerID, RequestID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
