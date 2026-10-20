"""Apply the additive Railway MySQL schema.

Run with Railway MySQL variables in the environment:
    python cloud_migrate.py
"""

from pathlib import Path

import mysql.connector

from iot_config import MYSQL_CONFIG


def _statements(sql_text):
    lines = [line for line in sql_text.splitlines()
             if not line.lstrip().startswith('--')]
    return [statement.strip() for statement in '\n'.join(lines).split(';')
            if statement.strip()]


def _table_exists(cursor, table_name):
    cursor.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_schema = DATABASE() AND table_name = %s",
        (table_name,),
    )
    return cursor.fetchone()[0] > 0


def _column_exists(cursor, table_name, column_name):
    cursor.execute(
        "SELECT COUNT(*) FROM information_schema.columns "
        "WHERE table_schema = DATABASE() AND table_name = %s "
        "AND column_name = %s",
        (table_name, column_name),
    )
    return cursor.fetchone()[0] > 0


def _migrate_supabase_snapshot_storage(cursor):
    """Detach request snapshots from the retired Railway IoT tables."""
    if not _table_exists(cursor, 'request_sensor_snapshots'):
        return

    if _column_exists(cursor, 'request_sensor_snapshots', 'iot_device_id'):
        if not _column_exists(cursor, 'request_sensor_snapshots', 'device_id'):
            cursor.execute(
                "ALTER TABLE request_sensor_snapshots "
                "ADD COLUMN device_id VARCHAR(80) NULL AFTER ZoneNo"
            )

        if _table_exists(cursor, 'iot_devices'):
            cursor.execute(
                "UPDATE request_sensor_snapshots s "
                "LEFT JOIN iot_devices d ON d.id = s.iot_device_id "
                "SET s.device_id = COALESCE(d.device_id, "
                "CONCAT('legacy-', s.iot_device_id)) "
                "WHERE s.device_id IS NULL"
            )
        else:
            cursor.execute(
                "UPDATE request_sensor_snapshots "
                "SET device_id = CONCAT('legacy-', iot_device_id) "
                "WHERE device_id IS NULL"
            )

        cursor.execute(
            "SELECT CONSTRAINT_NAME FROM information_schema.KEY_COLUMN_USAGE "
            "WHERE TABLE_SCHEMA = DATABASE() "
            "AND TABLE_NAME = 'request_sensor_snapshots' "
            "AND COLUMN_NAME = 'iot_device_id' "
            "AND REFERENCED_TABLE_NAME IS NOT NULL"
        )
        for (constraint_name,) in cursor.fetchall():
            safe_name = constraint_name.replace('`', '``')
            cursor.execute(
                f"ALTER TABLE request_sensor_snapshots "
                f"DROP FOREIGN KEY `{safe_name}`"
            )

        cursor.execute(
            "ALTER TABLE request_sensor_snapshots "
            "MODIFY device_id VARCHAR(80) NOT NULL, "
            "DROP COLUMN iot_device_id"
        )

    # Supabase is the only live IoT store. These Railway copies are retired
    # after their snapshot dependency has been removed.
    cursor.execute("DROP TABLE IF EXISTS sensor_readings")
    cursor.execute("DROP TABLE IF EXISTS iot_devices")


def main():
    schema_path = Path(__file__).with_name('cloud_schema.sql')
    connection = mysql.connector.connect(**MYSQL_CONFIG)
    cursor = connection.cursor()
    try:
        for statement in _statements(schema_path.read_text(encoding='utf-8')):
            cursor.execute(statement)
        _migrate_supabase_snapshot_storage(cursor)
        connection.commit()
        print('Cloud database schema is ready.')
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


if __name__ == '__main__':
    main()
