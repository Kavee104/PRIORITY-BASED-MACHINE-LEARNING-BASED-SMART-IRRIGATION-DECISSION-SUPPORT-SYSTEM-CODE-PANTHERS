"""Shared local configuration for Flask and IoT setup commands."""

import os


def _setting(local_name, railway_name, default):
    """Read local variable names first, then Railway MySQL aliases."""
    return os.environ.get(local_name) or os.environ.get(railway_name) or default


MYSQL_CONFIG = {
    'host': _setting('MYSQL_HOST', 'MYSQLHOST', 'localhost'),
    'user': _setting('MYSQL_USER', 'MYSQLUSER', 'root'),
    'password': _setting('MYSQL_PASSWORD', 'MYSQLPASSWORD', ''),
    'database': _setting('MYSQL_DATABASE', 'MYSQLDATABASE', 'smart_irrigation_db'),
    'port': int(_setting('MYSQL_PORT', 'MYSQLPORT', '3306')),
    'autocommit': True,
}

IOT_OFFLINE_SECONDS = int(os.environ.get('IOT_OFFLINE_SECONDS', '30'))
