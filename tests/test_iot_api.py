import hashlib
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import app as backend
import iot_store


class FakeConnection:
    def __init__(self, device=None):
        self.device = device
        self.statements = []
        self.readings = []
        self.last_seen = None
        self.closed = False
        self.committed = False
        self.rolled_back = False

    def cursor(self, dictionary=False):
        return self

    def execute(self, sql, params=()):
        self.statements.append((sql, params))
        if sql.startswith('INSERT INTO sensor_readings'):
            self.readings.append(params)
        elif sql.startswith('UPDATE iot_devices SET last_seen'):
            self.last_seen = datetime.now(timezone.utc)
            self.device['status'] = 'ONLINE'

    def fetchone(self):
        return self.device

    def start_transaction(self):
        pass

    def commit(self):
        self.committed = True

    def rollback(self):
        self.rolled_back = True

    def close(self):
        self.closed = True


class IotApiTests(unittest.TestCase):
    def setUp(self):
        self.client = backend.app.test_client()
        self.payload = {
            'deviceId': 'ESP32_ZONE_01',
            'deviceToken': 'test-token-for-isolated-tests',
            'moisture': 47,
            'temperature': 30.5,
        }

    def test_ingest_rejects_bad_input_before_database_access(self):
        with patch.object(backend, 'get_db_connection') as connection:
            self.assertEqual(self.client.post('/sensor-data', data='bad',
                              content_type='application/json').status_code, 400)
            for change in ({'moisture': -1}, {'moisture': '47'},
                           {'temperature': 200}, {'deviceId': ''},
                           {'deviceToken': ''}):
                response = self.client.post('/sensor-data', json={**self.payload, **change})
                self.assertEqual(response.status_code, 400)
            connection.assert_not_called()

    def test_unknown_and_invalid_token_are_rejected(self):
        for error, expected in ((iot_store.UnknownDevice(), 404),
                                (iot_store.InvalidDeviceToken(), 401)):
            connection = FakeConnection()
            with patch.object(backend, 'get_db_connection', return_value=connection), \
                 patch.object(backend.iot_store, 'record_reading', side_effect=error):
                response = self.client.post('/sensor-data', json=self.payload)
            self.assertEqual(response.status_code, expected)
            self.assertTrue(connection.closed)

    def test_database_unavailable_returns_503(self):
        with patch.object(backend, 'get_db_connection', return_value=None):
            response = self.client.post('/sensor-data', json=self.payload)
        self.assertEqual(response.status_code, 503)

    def test_device_write_checks_token_and_commits(self):
        valid_hash = hashlib.sha256(self.payload['deviceToken'].encode()).hexdigest()
        connection = FakeConnection({'id': 7, 'status': 'OFFLINE',
                                     'device_token_hash': valid_hash})
        iot_store.record_reading(connection, self.payload['deviceId'],
                                 self.payload['deviceToken'], 47, 30.5)
        self.assertTrue(connection.committed)
        self.assertTrue(any('INSERT INTO sensor_readings' in sql
                            for sql, _ in connection.statements))
        bad_connection = FakeConnection({'id': 7, 'status': 'OFFLINE',
                                         'device_token_hash': valid_hash})
        with self.assertRaises(iot_store.InvalidDeviceToken):
            iot_store.record_reading(bad_connection, self.payload['deviceId'],
                                     'wrong-token', 47, 30.5)
        self.assertTrue(bad_connection.rolled_back)
        self.assertFalse(bad_connection.committed)

    def test_post_registered_device_inserts_one_reading_and_updates_last_seen(self):
        token_hash = hashlib.sha256(self.payload['deviceToken'].encode()).hexdigest()
        connection = FakeConnection({'id': 1, 'status': 'OFFLINE',
                                     'device_token_hash': token_hash})
        with patch.object(backend, 'get_db_connection', return_value=connection):
            response = self.client.post('/sensor-data', json={
                **self.payload, 'moisture': 45, 'temperature': 30.5})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json['deviceId'], 'ESP32_ZONE_01')
        self.assertEqual(response.json['moisture'], 45)
        self.assertEqual(response.json['temperature'], 30.5)
        self.assertEqual(connection.readings, [(1, 45, 30.5)])
        self.assertIsNotNone(connection.last_seen)
        self.assertEqual(connection.device['status'], 'ONLINE')
        self.assertTrue(connection.committed)
        self.assertTrue(connection.closed)

    def test_post_registered_device_with_wrong_token_inserts_nothing(self):
        token_hash = hashlib.sha256('correct-secret-token'.encode()).hexdigest()
        connection = FakeConnection({'id': 1, 'status': 'OFFLINE',
                                     'device_token_hash': token_hash})
        with patch.object(backend, 'get_db_connection', return_value=connection):
            response = self.client.post('/sensor-data', json=self.payload)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(connection.readings, [])
        self.assertIsNone(connection.last_seen)
        self.assertFalse(connection.committed)
        self.assertTrue(connection.rolled_back)
        self.assertTrue(connection.closed)

    def test_farmer_identity_comes_from_signed_session(self):
        user = {'id': 98765, 'role': 'farmer', 'password_hash': 'unused'}
        token = backend._session_token('iot_test_user', user)
        sensor = {'deviceId': 'ESP32_ZONE_01', 'farmerId': 98765,
                  'zoneNo': 1, 'moisture': 47.0, 'temperature': 30.5,
                  'deviceStatus': 'ONLINE', 'lastSeen': None, 'recordedAt': None}
        with patch.dict(backend.users, {'iot_test_user': user}), \
             patch.object(backend, 'get_db_connection', return_value=FakeConnection()), \
             patch.object(backend.iot_store, 'list_latest', return_value=[sensor]) as latest:
            no_token = self.client.get('/api/user/sensor-data')
            response = self.client.get('/api/user/sensor-data',
                                       headers={'Authorization': f'Bearer {token}'})
        self.assertEqual(no_token.status_code, 401)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['farmerId'], 98765)
        self.assertEqual(latest.call_args.args[2], 98765)

    def test_admin_route_requires_existing_admin_key(self):
        self.assertEqual(self.client.get('/api/admin/sensors').status_code, 401)
        with patch.object(backend, 'get_db_connection', return_value=FakeConnection()), \
             patch.object(backend.iot_store, 'list_latest', return_value=[]):
            response = self.client.get('/api/admin/sensors',
                headers={'X-Admin-Key': backend.ADMIN_KEY})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['sensors'], [])

    def test_status_expires_after_timeout(self):
        old = datetime.now(timezone.utc) - timedelta(seconds=backend.IOT_OFFLINE_SECONDS + 2)
        recent = datetime.now(timezone.utc)
        self.assertFalse(iot_store._online({'status': 'ONLINE', 'last_seen': old},
                                           backend.IOT_OFFLINE_SECONDS))
        self.assertTrue(iot_store._online({'status': 'ONLINE', 'last_seen': recent},
                                          backend.IOT_OFFLINE_SECONDS))

    def test_request_snapshot_visible_only_to_owner_or_admin(self):
        user = {'id': 98765, 'role': 'farmer', 'password_hash': 'unused'}
        request_row = {'RequestID': 10, 'farmer_id': 98765, 'FieldID': 1,
                       'RequestTime': '2026-09-22 12:00:00', 'SoilMoisture': 47,
                       'SoilTemperature': 30.5, 'DeviceID': 'ESP32_ZONE_01'}
        with patch.dict(backend.users, {'iot_test_user': user}), \
             patch.object(backend, 'water_requests', [request_row]), \
             patch.object(backend, 'get_db_connection', return_value=None):
            token = backend._session_token('iot_test_user', user)
            anonymous = self.client.get('/my-requests/98765')
            owner = self.client.get('/my-requests/98765',
                headers={'Authorization': f'Bearer {token}'})
            legacy = self.client.get('/requests')
            admin = self.client.get('/admin/water-requests',
                headers={'X-Admin-Key': backend.ADMIN_KEY})
        self.assertNotIn('SoilMoisture', anonymous.json['requests'][0])
        self.assertEqual(owner.json['requests'][0]['SoilMoisture'], 47)
        self.assertNotIn('SoilMoisture', legacy.json['requests'][0])
        self.assertEqual(admin.json['requests'][0]['SoilMoisture'], 47)


if __name__ == '__main__':
    unittest.main()
