-- Additive IoT schema for smart_irrigation_db. Apply after selecting that database.
-- FarmerID and ZoneNo use the same integer identifiers as farmer/field_profile.
-- No FK to farmer/irrigation_request: this app also supports JSON-backed users
-- and requests, and the existing MySQL DDL is not part of this repository.

CREATE TABLE IF NOT EXISTS iot_devices (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  device_id VARCHAR(80) NOT NULL UNIQUE,
  device_name VARCHAR(120) NOT NULL,
  device_token_hash CHAR(64) NOT NULL,
  FarmerID INT NOT NULL,
  ZoneNo INT NOT NULL,
  status ENUM('OFFLINE', 'ONLINE', 'DISABLED') NOT NULL DEFAULT 'OFFLINE',
  last_seen DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_iot_devices_owner (FarmerID, ZoneNo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sensor_readings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  iot_device_id INT UNSIGNED NOT NULL,
  moisture DECIMAL(5,2) NOT NULL,
  temperature DECIMAL(6,2) NOT NULL,
  recorded_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_sensor_readings_device FOREIGN KEY (iot_device_id)
    REFERENCES iot_devices(id),
  INDEX idx_sensor_readings_latest (iot_device_id, recorded_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Immutable snapshot captured when a water request is submitted.
-- RequestID is intentionally not an FK because the app can create JSON-only
-- requests when MySQL irrigation_request is unavailable.
CREATE TABLE IF NOT EXISTS request_sensor_snapshots (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  RequestID INT NOT NULL,
  FarmerID INT NOT NULL,
  FieldID INT NOT NULL,
  ZoneNo INT NOT NULL,
  iot_device_id INT UNSIGNED NOT NULL,
  moisture DECIMAL(5,2) NOT NULL,
  temperature DECIMAL(6,2) NOT NULL,
  recorded_at DATETIME(6) NOT NULL,
  captured_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_request_snapshot_device FOREIGN KEY (iot_device_id)
    REFERENCES iot_devices(id),
  UNIQUE KEY uq_request_snapshot (RequestID, FarmerID, FieldID),
  INDEX idx_request_snapshot_lookup (FarmerID, RequestID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Example registration: replace all placeholders and use a long random token.
-- INSERT INTO iot_devices
--   (device_id, device_name, device_token_hash, FarmerID, ZoneNo)
-- VALUES
--   ('ESP32_ZONE_01', 'Zone 01 sensor', SHA2('REPLACE_WITH_RANDOM_TOKEN', 256), 1, 1);
