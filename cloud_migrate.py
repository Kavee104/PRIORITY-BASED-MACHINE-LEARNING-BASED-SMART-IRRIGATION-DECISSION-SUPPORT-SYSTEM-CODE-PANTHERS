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


def main():
    schema_path = Path(__file__).with_name('cloud_schema.sql')
    connection = mysql.connector.connect(**MYSQL_CONFIG)
    cursor = connection.cursor()
    try:
        for statement in _statements(schema_path.read_text(encoding='utf-8')):
            cursor.execute(statement)
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
