import unittest
from pathlib import Path
from unittest.mock import patch

import app as backend
from cloud_migrate import _statements


class _UserCursor:
    def __init__(self, rows):
        self.rows = rows
        self.statements = []
        self.closed = False

    def execute(self, sql, params=()):
        self.statements.append((sql, params))

    def fetchall(self):
        return self.rows

    def close(self):
        self.closed = True


class _UserConnection:
    def __init__(self, rows):
        self.user_cursor = _UserCursor(rows)
        self.closed = False

    def cursor(self, dictionary=False):
        if not dictionary:
            raise AssertionError('Persistent user load must use dictionary rows')
        return self.user_cursor

    def close(self):
        self.closed = True


class _PasswordCursor:
    def __init__(self):
        self.statements = []
        self.closed = False

    def execute(self, sql, params=()):
        self.statements.append((sql, params))

    def close(self):
        self.closed = True


class _PasswordConnection:
    def __init__(self):
        self.password_cursor = _PasswordCursor()
        self.committed = False
        self.rolled_back = False
        self.closed = False

    def cursor(self):
        return self.password_cursor

    def commit(self):
        self.committed = True

    def rollback(self):
        self.rolled_back = True

    def close(self):
        self.closed = True


class CloudDeploymentTests(unittest.TestCase):
    def test_cloud_schema_is_additive_and_complete(self):
        sql = Path('cloud_schema.sql').read_text(encoding='utf-8')
        statements = _statements(sql)
        normalized = '\n'.join(statements).upper()

        self.assertFalse(any(
            statement.lstrip().upper().startswith('DROP')
            for statement in statements
        ))
        for table in (
            'ZONE', 'FARMER', 'FIELD_PROFILE', 'IRRIGATION_REQUEST',
            'USERS', 'REQUEST_SENSOR_SNAPSHOTS',
        ):
            self.assertIn(f'CREATE TABLE IF NOT EXISTS {table}', normalized)
        self.assertNotIn('CREATE TABLE IF NOT EXISTS IOT_DEVICES', normalized)
        self.assertNotIn('CREATE TABLE IF NOT EXISTS SENSOR_READINGS', normalized)
        self.assertIn('DEVICE_ID VARCHAR(80) NOT NULL', normalized)

    def test_railway_starts_migration_before_gunicorn(self):
        config = Path('railway.toml').read_text(encoding='utf-8')
        migration_position = config.index('python cloud_migrate.py')
        gunicorn_position = config.index('gunicorn')
        self.assertLess(migration_position, gunicorn_position)
        self.assertIn('healthcheckPath = "/health"', config)

    def test_runtime_user_cache_loads_mysql_aliases(self):
        rows = [{
            'AccountID': 6,
            'Username': 'farmer6',
            'Email': 'farmer6@example.com',
            'PasswordHash': 'stored-hash',
            'FirstName': 'Test',
            'LastName': 'Farmer',
            'Role': 'farmer',
        }]
        connection = _UserConnection(rows)

        with patch.object(backend, 'get_db_connection',
                          return_value=connection), \
             patch.dict(backend.users, {}, clear=True):
            loaded = backend._load_users_from_mysql()
            self.assertEqual(loaded, 1)
            self.assertIs(
                backend.users['farmer6'],
                backend.users['farmer6@example.com'],
            )
            self.assertEqual(backend.users['farmer6']['id'], 6)

        self.assertTrue(connection.user_cursor.closed)
        self.assertTrue(connection.closed)

    def test_password_change_persists_to_users_and_farmer_tables(self):
        account = {
            'id': 6,
            'email': 'farmer6@example.com',
            'name': 'Test Farmer',
            'role': 'farmer',
            'password_hash': 'old-hash',
        }
        connection = _PasswordConnection()

        with patch.object(backend, 'get_db_connection',
                          return_value=connection), \
             patch.dict(backend.users, {
                 'farmer6': account,
                 'farmer6@example.com': account,
             }, clear=True):
            persisted = backend._persist_password_hash(
                'farmer6@example.com', account, 'new-hash')

        self.assertTrue(persisted)
        self.assertTrue(connection.committed)
        self.assertFalse(connection.rolled_back)
        sql = '\n'.join(statement for statement, _
                        in connection.password_cursor.statements)
        self.assertIn('INSERT INTO users', sql)
        self.assertIn('UPDATE farmer SET Password', sql)
        self.assertTrue(connection.password_cursor.closed)
        self.assertTrue(connection.closed)

    def test_password_persistence_reports_database_unavailable(self):
        with patch.object(backend, 'get_db_connection', return_value=None):
            self.assertFalse(backend._persist_password_hash(
                'farmer6', {'role': 'farmer'}, 'new-hash'))


if __name__ == '__main__':
    unittest.main()
