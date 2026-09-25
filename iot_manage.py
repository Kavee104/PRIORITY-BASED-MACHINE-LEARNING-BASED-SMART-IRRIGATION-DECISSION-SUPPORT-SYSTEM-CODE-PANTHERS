"""Apply the additive IoT schema and register a zone-owned ESP32 device."""

import argparse
import getpass
import hashlib
import json
import re
import secrets
from pathlib import Path

import mysql.connector

from iot_config import MYSQL_CONFIG


ROOT = Path(__file__).resolve().parent


def connect():
    return mysql.connector.connect(**MYSQL_CONFIG)


def migrate():
    lines = ROOT.joinpath('iot_schema.sql').read_text(encoding='utf-8').splitlines()
    statements = '\n'.join(line for line in lines if not line.lstrip().startswith('--'))
    conn = connect()
    try:
        cursor = conn.cursor()
        count = 0
        for statement in statements.split(';'):
            if statement.strip():
                cursor.execute(statement)
                count += 1
        cursor.close()
        print(f'Applied {count} additive IoT schema statements.')
    finally:
        conn.close()


def register(device_id, device_name, farmer_id, zone_no):
    if not re.fullmatch(r'[A-Za-z0-9_-]{3,80}', device_id):
        raise ValueError('device-id must use 3-80 letters, digits, underscores, or hyphens')
    if farmer_id <= 0 or zone_no <= 0:
        raise ValueError('farmer-id and zone-no must be positive integers')
    token = getpass.getpass('New device token (at least 16 characters): ')
    if len(token) < 16:
        raise ValueError('Device token must contain at least 16 characters')

    accounts = json.loads(ROOT.joinpath('users.json').read_text(encoding='utf-8'))
    owner_exists = any(
        info.get('id') == farmer_id and info.get('role') == 'farmer'
        for info in accounts.values())
    if not owner_exists:
        raise ValueError('No farmer account with that FarmerID exists in users.json')

    conn = connect()
    try:
        cursor = conn.cursor()
        try:
            cursor.execute(
                'SELECT 1 FROM field_profile WHERE FarmerID = %s AND ZoneNo = %s LIMIT 1',
                (farmer_id, zone_no))
            field_exists = cursor.fetchone() is not None
        except mysql.connector.Error:
            field_exists = False
        if not field_exists:
            fields = json.loads(ROOT.joinpath('fields.json').read_text(encoding='utf-8'))
            field_exists = any(int(field.get('ZoneNo', -1)) == zone_no
                               for field in fields.get(str(farmer_id), []))
        if not field_exists:
            raise ValueError('No field in that zone belongs to this farmer')
        cursor.execute(
            'INSERT INTO iot_devices '
            '(device_id, device_name, device_token_hash, FarmerID, ZoneNo) '
            'VALUES (%s, %s, %s, %s, %s)',
            (device_id, device_name, hashlib.sha256(token.encode('utf-8')).hexdigest(),
             farmer_id, zone_no))
        conn.commit()
        cursor.close()
        print(f'Registered {device_id} for FarmerID {farmer_id}, ZoneNo {zone_no}.')
        print('Copy the token into the ESP32 sketch; it cannot be recovered from MySQL.')
    finally:
        conn.close()


def reset_token(device_id):
    if not re.fullmatch(r'[A-Za-z0-9_-]{3,80}', device_id):
        raise ValueError('device-id must use 3-80 letters, digits, underscores, or hyphens')

    conn = connect()
    try:
        cursor = conn.cursor()
        try:
            conn.start_transaction()
            cursor.execute('SELECT id FROM iot_devices WHERE device_id = %s FOR UPDATE',
                           (device_id,))
            device = cursor.fetchone()
            if device is None:
                raise ValueError(f'Device {device_id} does not exist')

            token = secrets.token_urlsafe(32)  # 32 random bytes; 256 bits of entropy.
            token_hash = hashlib.sha256(token.encode('utf-8')).hexdigest()
            cursor.execute('UPDATE iot_devices SET device_token_hash = %s WHERE id = %s',
                           (token_hash, device[0]))
            conn.commit()
            return token
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()
    finally:
        conn.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('migrate', help='Create missing IoT tables')
    registration = commands.add_parser('register', help='Register one ESP32')
    registration.add_argument('--device-id', required=True)
    registration.add_argument('--device-name', required=True)
    registration.add_argument('--farmer-id', type=int, required=True)
    registration.add_argument('--zone-no', type=int, required=True)
    reset = commands.add_parser('reset-token', help='Replace the token for an existing ESP32')
    reset.add_argument('--device-id', required=True)
    args = parser.parse_args()
    try:
        if args.command == 'migrate':
            migrate()
        elif args.command == 'reset-token':
            print(f'New device token: {reset_token(args.device_id)}')
        else:
            register(args.device_id, args.device_name, args.farmer_id, args.zone_no)
    except (mysql.connector.Error, ValueError) as exc:
        parser.exit(1, f'IoT setup failed: {exc}\n')
