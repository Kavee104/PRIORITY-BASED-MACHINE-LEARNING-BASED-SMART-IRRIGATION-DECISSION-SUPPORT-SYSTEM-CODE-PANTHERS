"""MySQL helpers for the single-ESP32 prototype and future zone devices."""

import hashlib
import hmac
from datetime import datetime, timedelta, timezone


class UnknownDevice(Exception):
    pass


class InvalidDeviceToken(Exception):
    pass


def _utc_string(value):
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _online(device, offline_seconds):
    seen = device.get('last_seen')
    if device.get('status') == 'DISABLED' or seen is None:
        return False
    if seen.tzinfo is None:
        seen = seen.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc) - seen <= timedelta(seconds=offline_seconds)


def record_reading(conn, device_id, device_token, moisture, temperature):
    cursor = conn.cursor(dictionary=True)
    try:
        conn.start_transaction()
        cursor.execute(
            "SELECT id, device_token_hash, status FROM iot_devices "
            "WHERE device_id = %s FOR UPDATE", (device_id,))
        device = cursor.fetchone()
        if not device or device['status'] == 'DISABLED':
            raise UnknownDevice()
        token_hash = hashlib.sha256(device_token.encode('utf-8')).hexdigest()
        if not hmac.compare_digest(token_hash, device['device_token_hash']):
            raise InvalidDeviceToken()
        cursor.execute(
            "INSERT INTO sensor_readings (iot_device_id, moisture, temperature, recorded_at) "
            "VALUES (%s, %s, %s, UTC_TIMESTAMP(6))",
            (device['id'], moisture, temperature))
        cursor.execute(
            "UPDATE iot_devices SET last_seen = UTC_TIMESTAMP(6), status = 'ONLINE' "
            "WHERE id = %s", (device['id'],))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()


def list_latest(conn, offline_seconds, farmer_id=None):
    cursor = conn.cursor(dictionary=True)
    try:
        query = (
            "SELECT id, device_id, device_name, FarmerID, ZoneNo, status, last_seen "
            "FROM iot_devices"
        )
        params = ()
        if farmer_id is not None:
            query += " WHERE FarmerID = %s"
            params = (farmer_id,)
        query += " ORDER BY id"
        cursor.execute(query, params)
        devices = cursor.fetchall()
        result = []
        for device in devices:
            cursor.execute(
                "SELECT moisture, temperature, recorded_at FROM sensor_readings "
                "WHERE iot_device_id = %s ORDER BY recorded_at DESC, id DESC LIMIT 1",
                (device['id'],))
            reading = cursor.fetchone()
            result.append({
                'deviceId': device['device_id'],
                'deviceName': device['device_name'],
                'farmerId': device['FarmerID'],
                'zoneNo': device['ZoneNo'],
                'moisture': float(reading['moisture']) if reading else None,
                'temperature': float(reading['temperature']) if reading else None,
                'deviceStatus': 'ONLINE' if _online(device, offline_seconds) else 'OFFLINE',
                'lastSeen': _utc_string(device['last_seen']),
                'recordedAt': _utc_string(reading['recorded_at']) if reading else None,
            })
        return result
    finally:
        cursor.close()


def latest_for_field(conn, farmer_id, zone_no, offline_seconds):
    devices = list_latest(conn, offline_seconds, farmer_id)
    matching = [d for d in devices if d['zoneNo'] == zone_no and d['recordedAt']]
    return max(matching, key=lambda d: d['recordedAt']) if matching else None


def save_request_snapshot(conn, request_id, farmer_id, field_id, zone_no, reading):
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id FROM iot_devices WHERE device_id = %s", (reading['deviceId'],))
        device = cursor.fetchone()
        if not device:
            return
        cursor.execute(
            "INSERT INTO request_sensor_snapshots "
            "(RequestID, FarmerID, FieldID, ZoneNo, iot_device_id, moisture, "
            "temperature, recorded_at) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
            (request_id, farmer_id, field_id, zone_no, device['id'],
             reading['moisture'], reading['temperature'],
             datetime.fromisoformat(reading['recordedAt']).replace(tzinfo=None)))
    finally:
        cursor.close()


def request_snapshots(conn, request_ids):
    if not request_ids:
        return {}
    cursor = conn.cursor(dictionary=True)
    try:
        placeholders = ','.join(['%s'] * len(request_ids))
        cursor.execute(
            "SELECT s.RequestID, s.FarmerID, s.FieldID, s.ZoneNo, s.moisture, "
            "s.temperature, s.recorded_at, d.device_id FROM request_sensor_snapshots s "
            "JOIN iot_devices d ON d.id = s.iot_device_id "
            f"WHERE s.RequestID IN ({placeholders})", tuple(request_ids))
        return {
            (row['RequestID'], row['FarmerID'], row['FieldID']): {
                'SoilMoisture': float(row['moisture']),
                'SoilTemperature': float(row['temperature']),
                'SensorRecordedAt': _utc_string(row['recorded_at']),
                'DeviceID': row['device_id'],
                'ZoneNo': row['ZoneNo'],
            }
            for row in cursor.fetchall()
        }
    finally:
        cursor.close()


def history(conn, device_id, limit, farmer_id=None):
    cursor = conn.cursor(dictionary=True)
    try:
        query = "SELECT id, FarmerID FROM iot_devices WHERE device_id = %s"
        params = [device_id]
        if farmer_id is not None:
            query += " AND FarmerID = %s"
            params.append(farmer_id)
        cursor.execute(query, tuple(params))
        device = cursor.fetchone()
        if not device:
            raise UnknownDevice()
        cursor.execute(
            "SELECT moisture, temperature, recorded_at FROM sensor_readings "
            "WHERE iot_device_id = %s ORDER BY recorded_at DESC, id DESC LIMIT %s",
            (device['id'], limit))
        return [{
            'moisture': float(row['moisture']),
            'temperature': float(row['temperature']),
            'recordedAt': _utc_string(row['recorded_at']),
        } for row in cursor.fetchall()]
    finally:
        cursor.close()
