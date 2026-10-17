-- User account table for the Smart Irrigation application.
-- Run after selecting smart_irrigation_db, or let app.py create it at startup.

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
