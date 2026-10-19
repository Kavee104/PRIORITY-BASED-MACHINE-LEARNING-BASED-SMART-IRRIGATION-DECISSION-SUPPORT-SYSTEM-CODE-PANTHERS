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
        self.lastrowid = 500

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

    def test_mysql_utc_request_time_is_displayed_in_sri_lanka_time(self):
        utc_time = datetime(2026, 10, 19, 7, 30, 0)
        self.assertEqual(
            backend._format_utc_as_local(utc_time),
            '2026-10-19 13:00:00',
        )

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

    def test_admin_route_accepts_signed_admin_session_only(self):
        admin_user = {'id': 1, 'role': 'admin', 'password_hash': 'unused'}
        farmer_user = {'id': 2, 'role': 'farmer', 'password_hash': 'unused'}
        with patch.dict(backend.users, {
                'mobile_admin': admin_user,
                'mobile_farmer': farmer_user,
             }), patch.object(backend, 'get_db_connection', return_value=FakeConnection()), \
             patch.object(backend.iot_store, 'list_latest', return_value=[]):
            admin_token = backend._session_token('mobile_admin', admin_user)
            farmer_token = backend._session_token('mobile_farmer', farmer_user)
            admin_response = self.client.get(
                '/api/admin/sensors',
                headers={'Authorization': f'Bearer {admin_token}'})
            farmer_response = self.client.get(
                '/api/admin/sensors',
                headers={'Authorization': f'Bearer {farmer_token}'})

        self.assertEqual(admin_response.status_code, 200)
        self.assertEqual(farmer_response.status_code, 401)

    def test_builtin_admin_login_uses_railway_admin_password(self):
        stale_admin = {
            'id': 1,
            'role': 'admin',
            'password_hash': backend.generate_password_hash('old-password'),
        }
        with patch.dict(backend.os.environ, {
                'ADMIN_PASSWORD': 'current-railway-password',
             }), patch.dict(backend.users, {'admin': stale_admin}, clear=True):
            accepted = self.client.post('/login', json={
                'email': 'admin',
                'password': 'current-railway-password',
            })
            rejected = self.client.post('/login', json={
                'email': 'admin',
                'password': 'old-password',
            })

        self.assertEqual(accepted.status_code, 200)
        self.assertTrue(accepted.json.get('session_token'))
        self.assertEqual(rejected.status_code, 401)

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

    def test_water_request_keeps_authenticated_supabase_snapshot(self):
        user = {'id': 98765, 'role': 'farmer', 'password_hash': 'unused'}
        token = backend._session_token('iot_test_user', user)
        payload = {
            'farmer_id': 98765,
            'field_id': 4,
            'area_acres': 3.5,
            'sensor_snapshot': {
                'moisture': 47,
                'temperature': 30.5,
                'zone_no': 2,
                'device_id': 'ESP32_ZONE_02',
                'recorded_at': '2026-09-30T05:18:45.492132Z',
            },
        }
        fields = {98765: [{'FieldID': 4, 'ZoneNo': 2, 'Size': 3.5}]}
        field_connection = FakeConnection({'ZoneNo': 2, 'Size': 3.5})
        request_connection = FakeConnection()
        with (
            patch.dict(backend.users, {'iot_test_user': user}),
            patch.object(backend, 'farmer_fields', fields),
            patch.object(backend, 'water_requests', []),
            patch.object(backend, 'get_db_connection') as get_connection,
            patch.object(backend, '_write_requests_file'),
        ):
            get_connection.side_effect = [field_connection, request_connection, None]
            response = self.client.post(
                '/request-water', json=payload,
                headers={'Authorization': f'Bearer {token}'})

        self.assertEqual(response.status_code, 201)
        saved = response.json['request']
        self.assertEqual(saved['SoilMoisture'], 47.0)
        self.assertEqual(saved['SoilTemperature'], 30.5)
        self.assertEqual(saved['DeviceID'], 'ESP32_ZONE_02')
        self.assertEqual(saved['ZoneNo'], 2)
        self.assertTrue(request_connection.committed)
        self.assertTrue(any(
            sql.startswith('INSERT INTO irrigation_request')
            for sql, _ in request_connection.statements))

    def test_water_request_does_not_report_success_without_database(self):
        user = {'id': 98765, 'role': 'farmer', 'password_hash': 'unused'}
        token = backend._session_token('iot_test_user', user)
        with patch.dict(backend.users, {'iot_test_user': user}), \
             patch.object(backend, 'water_requests', []), \
             patch.object(backend, 'get_db_connection', return_value=None), \
             patch.object(backend, '_write_requests_file') as write_requests:
            response = self.client.post(
                '/request-water',
                json={'farmer_id': 98765, 'field_id': 4},
                headers={'Authorization': f'Bearer {token}'})
            self.assertEqual(backend.water_requests, [])

        self.assertEqual(response.status_code, 503)
        write_requests.assert_not_called()

    def test_client_snapshot_must_match_requested_zone(self):
        snapshot = backend._validated_client_sensor_snapshot({
            'sensor_snapshot': {
                'moisture': 47,
                'temperature': 30.5,
                'zone_no': 9,
                'device_id': 'ESP32_ZONE_09',
                'recorded_at': '2026-09-30T05:18:45Z',
            },
        }, expected_zone_no=2)
        self.assertIsNone(snapshot)

    def test_admin_request_uses_live_supabase_values_when_snapshot_is_missing(self):
        request_rows = [{
            'RequestID': 14,
            'farmer_id': 6,
            'FieldID': 9,
            'ZoneName': 'Zone 1 (Field #9)',
        }]
        live_values = {
            (6, 1): {
                'SoilMoisture': 0.0,
                'SoilTemperature': 33.6,
                'SensorRecordedAt': '2026-09-30T05:39:04.580009+00:00',
                'DeviceID': 'ESP32_ZONE_01',
                'ZoneNo': 1,
                'SensorSource': 'supabase_live',
            },
        }
        with patch.object(backend, '_supabase_latest_sensors',
                          return_value=live_values):
            backend._attach_live_admin_sensor_values(request_rows)

        self.assertEqual(request_rows[0]['SoilMoisture'], 0.0)
        self.assertEqual(request_rows[0]['SoilTemperature'], 33.6)
        self.assertEqual(request_rows[0]['DeviceID'], 'ESP32_ZONE_01')

    def test_priority_schedule_adds_varied_demo_zones(self):
        real_request = {
            'RequestID': 15,
            'farmer_id': 6,
            'FieldID': 9,
            'ZoneName': 'Zone 1 (Field #9)',
            'SoilMoisture': 36.5,
            'SoilTemperature': 28.4,
            'AreaAcres': 11.0,
            'Status': 'Pending',
        }
        with patch.object(backend, 'water_requests', [real_request]), \
             patch.object(backend, 'get_weather_forecast', return_value=0.0), \
             patch.object(backend, 'get_previous_day_rainfall', return_value=1.2):
            response = self.client.get('/priority-schedule')

        self.assertEqual(response.status_code, 200)
        schedule = response.json['schedule']
        names = {item['ZoneName'] for item in schedule}
        self.assertTrue({'Zone 1', 'Zone 2', 'Zone 3', 'Zone 4'} <= names)
        demo_moistures = {
            item['AvgSoilMoisture'] for item in schedule
            if item['ZoneName'] in {'Zone 2', 'Zone 3', 'Zone 4'}
        }
        self.assertEqual(len(demo_moistures), 3)

    def test_password_otp_is_never_exposed_when_email_is_not_configured(self):
        user = {
            'id': 98765,
            'role': 'farmer',
            'email': 'farmer@example.com',
            'password_hash': 'unused',
        }
        with patch.dict(backend.users, {'farmer@example.com': user}, clear=True), \
             patch.dict(backend.password_reset_otps, {}, clear=True), \
             patch.object(backend, '_send_reset_otp_email', return_value=False):
            response = self.client.post(
                '/forgot-password', json={'email': 'farmer@example.com'})
            self.assertEqual(response.status_code, 503)
            self.assertNotIn('dev_otp', response.json)
            self.assertNotIn('otp', response.json)
            self.assertEqual(backend.password_reset_otps, {})

    def test_password_otp_is_stored_only_after_email_is_sent(self):
        user = {
            'id': 98765,
            'role': 'farmer',
            'email': 'registered@example.com',
            'password_hash': 'unused',
        }
        with patch.dict(backend.users, {'farmer_login': user}, clear=True), \
             patch.dict(backend.password_reset_otps, {}, clear=True), \
             patch.object(backend, '_send_reset_otp_email', return_value=True) as send:
            response = self.client.post(
                '/forgot-password', json={'email': 'farmer_login'})

            self.assertEqual(response.status_code, 200)
            self.assertNotIn('dev_otp', response.json)
            self.assertNotIn('otp', response.json)
            self.assertEqual(len(backend.password_reset_otps), 1)
            send.assert_called_once()
            self.assertEqual(send.call_args.args[0], 'registered@example.com')

    def test_verified_password_reset_succeeds_without_mysql(self):
        user = {
            'id': 98765,
            'role': 'farmer',
            'email': 'registered@example.com',
            'password_hash': backend.generate_password_hash('old-password'),
        }
        otp_record = {
            'any:registered@example.com': {
                'otp': '654321',
                'expires_at': backend.time.time() + 600,
                'verified': True,
            },
        }
        with patch.dict(backend.users, {'registered@example.com': user}, clear=True), \
             patch.dict(backend.password_reset_otps, otp_record, clear=True), \
             patch.object(backend, 'get_db_connection', return_value=None), \
             patch.object(backend, '_write_users_file'):
            response = self.client.post('/reset-password', json={
                'email': 'registered@example.com',
                'otp': '654321',
                'new_password': 'new-secure-password',
            })

            self.assertEqual(response.status_code, 200)
            self.assertTrue(backend.check_password_hash(
                user['password_hash'], 'new-secure-password'))
            self.assertEqual(backend.password_reset_otps, {})

    def test_signup_does_not_report_success_when_mysql_is_unavailable(self):
        with patch.dict(backend.users, {}, clear=True), \
             patch.object(backend, 'get_db_connection', return_value=None), \
             patch.object(backend, '_write_users_file'):
            response = self.client.post('/signup', json={
                'f_name': 'Test',
                'l_name': 'Farmer',
                'email': 'new-farmer@example.com',
                'password': 'secure-password',
            })

            self.assertEqual(response.status_code, 503)
            self.assertEqual(backend.users, {})

    def test_signup_commits_farmer_to_mysql_before_local_cache(self):
        insert_connection = FakeConnection()
        with patch.dict(backend.users, {}, clear=True), \
             patch.object(backend, 'get_db_connection',
                          side_effect=[None, insert_connection]), \
             patch.object(backend, '_write_users_file'):
            response = self.client.post('/signup', json={
                'f_name': 'Test',
                'l_name': 'Farmer',
                'email': 'new-farmer@example.com',
                'password': 'secure-password',
            })

            self.assertEqual(response.status_code, 201)
            self.assertTrue(insert_connection.committed)
            self.assertTrue(any(
                sql.startswith('INSERT INTO farmer')
                for sql, _ in insert_connection.statements))
            self.assertTrue(any(
                sql.strip().startswith('CREATE TABLE IF NOT EXISTS users')
                for sql, _ in insert_connection.statements))
            self.assertTrue(any(
                sql.startswith('INSERT INTO users')
                for sql, _ in insert_connection.statements))
            self.assertIn('new-farmer@example.com', backend.users)

    def test_admin_created_user_is_committed_to_mysql(self):
        connection = FakeConnection()
        with patch.dict(backend.users, {}, clear=True), \
             patch.object(backend, 'get_db_connection', return_value=connection), \
             patch.object(backend, '_write_users_file'):
            response = self.client.post(
                '/admin/create-user',
                json={
                    'username': 'new_officer',
                    'password': 'secure-password',
                    'role': 'officer',
                },
                headers={'X-Admin-Key': backend.ADMIN_KEY},
            )

            self.assertEqual(response.status_code, 200)
            self.assertTrue(connection.committed)
            self.assertTrue(any(
                sql.startswith('INSERT INTO users')
                for sql, _ in connection.statements))
            self.assertEqual(backend.users['new_officer']['role'], 'officer')


if __name__ == '__main__':
    unittest.main()
