"""Shared local configuration for Flask and IoT setup commands."""

import os


MYSQL_CONFIG = {
    'host': os.environ.get('MYSQL_HOST', 'localhost'),
    'user': os.environ.get('MYSQL_USER', 'root'),
    'password': os.environ.get('MYSQL_PASSWORD', ''),
    'database': os.environ.get('MYSQL_DATABASE', 'smart_irrigation_db'),
    'port': int(os.environ.get('MYSQL_PORT', '3306')),
    'autocommit': True,
}

IOT_OFFLINE_SECONDS = int(os.environ.get('IOT_OFFLINE_SECONDS', '30'))
