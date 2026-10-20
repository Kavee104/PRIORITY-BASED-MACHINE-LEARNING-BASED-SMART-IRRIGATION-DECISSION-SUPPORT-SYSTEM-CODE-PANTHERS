import joblib

# python -m pip install requests (terminal එකේ දාන්න)
import os
import json
import random
import requests
import smtplib
import time
import math
import secrets
import datetime
from zoneinfo import ZoneInfo
from email.message import EmailMessage
from flask import Flask, jsonify, request
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
import iot_store
from iot_config import MYSQL_CONFIG, IOT_OFFLINE_SECONDS
try:
  from flask_cors import CORS
except ImportError:
  CORS = None
from werkzeug.security import generate_password_hash, check_password_hash
import pandas as pd

APP_TIMEZONE = ZoneInfo(os.environ.get('APP_TIMEZONE', 'Asia/Colombo'))


def _local_now():
  return datetime.datetime.now(datetime.timezone.utc).astimezone(APP_TIMEZONE)


def _format_utc_as_local(value):
  """Format a MySQL UTC DATETIME value in the application's local timezone."""
  if isinstance(value, str):
    try:
      value = datetime.datetime.fromisoformat(value)
    except ValueError:
      return value
  if not isinstance(value, datetime.datetime):
    return str(value)
  if value.tzinfo is None:
    value = value.replace(tzinfo=datetime.timezone.utc)
  return value.astimezone(APP_TIMEZONE).strftime('%Y-%m-%d %H:%M:%S')

app = Flask(__name__)
IS_RAILWAY = bool(
  os.environ.get('RAILWAY_ENVIRONMENT') or os.environ.get('RAILWAY_PROJECT_ID')
)
LOCAL_JSON_WRITES_ENABLED = os.environ.get(
  'ENABLE_LOCAL_JSON_WRITES', '0' if IS_RAILWAY else '1'
).strip().lower() in {'1', 'true', 'yes', 'on'}
if CORS is not None:
  CORS(app, resources={r"/*": {"origins": "*"}})
else:
  @app.after_request
  def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization,X-Admin-Key'
    response.headers['Access-Control-Allow-Methods'] = 'GET,POST,PUT,DELETE,OPTIONS'
    return response

# Simple admin key for protected admin actions. Set ADMIN_KEY env var in production.
ADMIN_KEY = os.environ.get('ADMIN_KEY', 'supersecretadminkey')
SUPABASE_URL = os.environ.get(
  'SUPABASE_URL', 'https://bsmhjdwtbpbhlktjmocj.supabase.co').rstrip('/')
SUPABASE_ANON_KEY = os.environ.get(
  'SUPABASE_ANON_KEY', 'sb_publishable_1kgHrzhwsGkpUL3bNS0EBg_Jd42jPvD')
SESSION_MAX_AGE_SECONDS = 12 * 60 * 60
session_signer = URLSafeTimedSerializer(
  os.environ.get('SESSION_SECRET') or secrets.token_hex(32), salt='farmer-session')

# ---------------------------------------------------------------------------
# MySQL Database Configuration (smart_irrigation_db)
# ---------------------------------------------------------------------------
try:
  import mysql.connector
except ImportError:
  mysql = None

def get_db_connection():
  try:
    if mysql:
      return mysql.connector.connect(**MYSQL_CONFIG)
  except Exception as e:
    print("MySQL Connection Error:", e)
  return None

# In-memory users store. In production replace with persistent DB.
# Structure: username -> {password_hash: str, role: 'admin'|'officer'|'farmer'}
users = {}

# Persist users to a JSON file so admin survives restarts.
USERS_FILE = os.path.join(os.path.dirname(__file__), 'users.json')
DEFAULT_ADMIN_USERNAME = 'admin'
DEFAULT_ADMIN_PASSWORD = 'admin'
OTP_EXPIRY_SECONDS = 10 * 60
password_reset_otps = {}

def _write_users_file(u):
  if not LOCAL_JSON_WRITES_ENABLED:
    return
  try:
    with open(USERS_FILE, 'w', encoding='utf-8') as fh:
      json.dump(u, fh, indent=2, ensure_ascii=False)
  except Exception as e:
    print('Failed to write users file:', e)

def _load_or_init_users():
  # If users.json exists load it, otherwise create default admin and write file.
  default_admin_password = os.environ.get('ADMIN_PASSWORD', DEFAULT_ADMIN_PASSWORD)
  if os.path.exists(USERS_FILE):
    try:
      with open(USERS_FILE, 'r', encoding='utf-8') as fh:
        loaded = json.load(fh)
        # If file contains plaintext 'password', convert to password_hash and persist.
        changed = False
        for uname, info in list(loaded.items()):
          if 'password' in info and 'password_hash' not in info:
            info['password_hash'] = generate_password_hash(info['password'])
            del info['password']
            changed = True
          if 'id' not in info:
            info['id'] = random.randint(10000, 99999)
            changed = True
        if changed:
          _write_users_file(loaded)
        admin = loaded.get(DEFAULT_ADMIN_USERNAME)
        if (
            admin is None
            or admin.get('role') != 'admin'
            or not check_password_hash(admin.get('password_hash', ''), default_admin_password)
        ):
          loaded[DEFAULT_ADMIN_USERNAME] = {
            'id': 1,
            'password_hash': generate_password_hash(default_admin_password),
            'role': 'admin'
          }
          changed = True
        if changed:
          _write_users_file(loaded)
        return loaded
    except Exception as e:
      print('Failed to load users file, falling back to in-memory. Error:', e)

  # Create default admin user
  admin_user = {
    'id': 1,
    'password_hash': generate_password_hash(default_admin_password),
    'role': 'admin'
  }
  u = {DEFAULT_ADMIN_USERNAME: admin_user}
  try:
    _write_users_file(u)
  except Exception as e:
    print('Failed to create users file:', e)
  return u

users = _load_or_init_users()

# Ensure in-memory users have password_hash keys for runtime checks.
for uname, info in list(users.items()):
  if 'password_hash' not in info:
    pw = info.get('password', '')
    users[uname]['password_hash'] = generate_password_hash(pw)
    users[uname].pop('password', None)
  # keep 'role' as-is
_write_users_file(users)


# ---------------------------------------------------------------------------
# File-based water requests & fields persistence
# ---------------------------------------------------------------------------
FIELDS_FILE = os.path.join(os.path.dirname(__file__), 'fields.json')
REQUESTS_FILE = os.path.join(os.path.dirname(__file__), 'requests.json')

def _write_fields_file(f_fields):
  if not LOCAL_JSON_WRITES_ENABLED:
    return
  try:
    # Convert integer keys to string keys for JSON serialization
    serializable = {str(k): v for k, v in f_fields.items()}
    with open(FIELDS_FILE, 'w', encoding='utf-8') as fh:
      json.dump(serializable, fh, indent=2, ensure_ascii=False)
  except Exception as e:
    print('Failed to write fields file:', e)

def _load_fields():
  if os.path.exists(FIELDS_FILE):
    try:
      with open(FIELDS_FILE, 'r', encoding='utf-8') as fh:
        loaded = json.load(fh)
        return {int(k): v for k, v in loaded.items()}
    except Exception as e:
      print('Failed to load fields file:', e)
  return {}

def _write_requests_file(w_requests):
  if not LOCAL_JSON_WRITES_ENABLED:
    return
  try:
    with open(REQUESTS_FILE, 'w', encoding='utf-8') as fh:
      json.dump(w_requests, fh, indent=2, ensure_ascii=False)
  except Exception as e:
    print('Failed to write requests file:', e)

def _load_requests():
  if os.path.exists(REQUESTS_FILE):
    try:
      with open(REQUESTS_FILE, 'r', encoding='utf-8') as fh:
        return json.load(fh)
    except Exception as e:
      print('Failed to load requests file:', e)
  return []


def _attach_request_snapshots(requests_list):
  ids = [r['RequestID'] for r in requests_list if isinstance(r.get('RequestID'), int)]
  if not ids:
    return requests_list
  conn = get_db_connection()
  if not conn:
    return requests_list
  try:
    snapshots = iot_store.request_snapshots(conn, ids)
    for item in requests_list:
      snapshot = snapshots.get((item.get('RequestID'), item.get('farmer_id'), item.get('FieldID')))
      if snapshot:
        item.update(snapshot)
  except Exception as e:
    print('Sensor snapshot read error:', e)
  finally:
    conn.close()
  return requests_list


def _request_zone_no(item):
  try:
    return int(item.get('ZoneNo'))
  except (TypeError, ValueError):
    match = re.search(r'Zone\s+(\d+)', str(item.get('ZoneName', '')), re.IGNORECASE)
    return int(match.group(1)) if match else None


def _supabase_latest_sensors():
  """Return the latest Supabase reading keyed by farmer and zone."""
  if not SUPABASE_URL or not SUPABASE_ANON_KEY:
    return {}
  headers = {
    'apikey': SUPABASE_ANON_KEY,
    'Authorization': f'Bearer {SUPABASE_ANON_KEY}',
  }
  try:
    device_response = requests.get(
      f'{SUPABASE_URL}/rest/v1/iot_devices',
      headers=headers,
      params={
        'select': 'device_id,farmer_id,zone_no,last_seen',
        'active': 'eq.true',
      },
      timeout=3,
    )
    device_response.raise_for_status()
    latest = {}
    for device in device_response.json():
      farmer_id = device.get('farmer_id')
      zone_no = device.get('zone_no')
      device_id = device.get('device_id')
      if farmer_id is None or zone_no is None or not device_id:
        continue
      reading_response = requests.get(
        f'{SUPABASE_URL}/rest/v1/sensor_readings',
        headers=headers,
        params={
          'select': 'moisture,temperature,recorded_at',
          'device_id': f'eq.{device_id}',
          'order': 'recorded_at.desc',
          'limit': '1',
        },
        timeout=3,
      )
      reading_response.raise_for_status()
      readings = reading_response.json()
      if not readings:
        continue
      reading = readings[0]
      latest[(int(farmer_id), int(zone_no))] = {
        'SoilMoisture': float(reading['moisture']),
        'SoilTemperature': float(reading['temperature']),
        'SensorRecordedAt': reading.get('recorded_at'),
        'DeviceID': str(device_id),
        'ZoneNo': int(zone_no),
        'SensorSource': 'supabase_live',
      }
    return latest
  except Exception as e:
    print('Supabase sensor read error:', e)
    return {}


def _attach_live_admin_sensor_values(requests_list):
  """Fill missing admin request values using the assigned live zone sensor."""
  needs_live_reading = any(
    item.get('SoilMoisture') is None or item.get('SoilTemperature') is None
    for item in requests_list
  )
  if not needs_live_reading:
    return requests_list

  latest = _supabase_latest_sensors()
  for item in requests_list:
    try:
      farmer_id = int(item.get('farmer_id', item.get('FarmerID')))
    except (TypeError, ValueError):
      continue
    sensor = latest.get((farmer_id, _request_zone_no(item)))
    if sensor:
      item.update(sensor)
  return requests_list

water_requests = _load_requests()
_next_request_id = max([r.get('RequestID', 0) for r in water_requests], default=0) + 1

farmer_fields = _load_fields()

# Audit trail log
audit_log = []  # list of dicts with keys: timestamp, action, user, details


def _audit(action, user='system', details=''):
  """Append an entry to the audit trail."""
  audit_log.insert(0, {
    'timestamp': _local_now().strftime('%Y-%m-%d %H:%M:%S'),
    'action': action,
    'user': user,
    'details': details,
  })


# No default farmer fields seeded for demo (display only newly added fields)

_audit('SYSTEM_INIT', 'system', 'Smart Irrigation backend initialized')


def _find_user(identifier):
  username = (identifier or '').strip()
  if not username:
    return None, None
  if username in users:
    return username, users[username]
  lowered = username.lower()
  if lowered in users:
    return lowered, users[lowered]
  return username, None


def _farmer_display_name(farmer_id, database_name=None):
  """Return a stable farmer name even when the legacy farmer row is blank."""
  database_name = str(database_name or '').strip()
  fallback_label = f'Farmer #{farmer_id}'
  if database_name and database_name != fallback_label:
    return database_name

  seen_accounts = set()
  for account in users.values():
    identity = id(account)
    if identity in seen_accounts:
      continue
    seen_accounts.add(identity)
    try:
      same_farmer = int(account.get('id')) == int(farmer_id)
    except (TypeError, ValueError):
      same_farmer = False
    if same_farmer and str(account.get('role') or '').lower() == 'farmer':
      name = str(account.get('name') or '').strip()
      if name:
        return name
      email = str(account.get('email') or '').strip()
      if email:
        return email

  return database_name or fallback_label


def _unique_user_accounts():
  """Collapse username/email aliases into one record per real account."""
  unique = {}
  for login_name, account in users.items():
    role = str(account.get('role') or 'farmer').lower()
    account_id = account.get('id')
    email = str(account.get('email') or '').strip().lower()
    identity = (role, account_id, email or login_name.strip().lower())
    candidate = {
      'id': account_id,
      'username': login_name,
      'email': email or None,
      'name': str(account.get('name') or '').strip() or login_name,
      'role': role,
    }
    existing = unique.get(identity)
    if existing is None or (
      '@' in str(existing.get('username') or '') and '@' not in login_name
    ):
      unique[identity] = candidate
  return list(unique.values())


def _session_token(username, user):
  canonical_username = next((key for key, record in users.items() if record is user), username)
  return session_signer.dumps({
    'username': canonical_username,
    'farmer_id': user.get('id'),
    'role': user.get('role'),
  })


def _current_farmer_id():
  header = request.headers.get('Authorization', '')
  if not header.startswith('Bearer '):
    return None
  try:
    payload = session_signer.loads(
      header[7:], max_age=SESSION_MAX_AGE_SECONDS)
  except (BadSignature, SignatureExpired):
    return None
  if payload.get('role') != 'farmer':
    return None
  user = users.get(payload.get('username'))
  farmer_id = payload.get('farmer_id')
  if not user or user.get('role') != 'farmer' or user.get('id') != farmer_id:
    return None
  return farmer_id


def _send_reset_otp_email(recipient, otp):
  # Railway trial/free environments can block outbound SMTP ports. Brevo's
  # HTTPS API avoids that restriction while keeping SMTP as a local fallback.
  brevo_api_key = os.environ.get('BREVO_API_KEY', '').strip()
  brevo_sender_email = os.environ.get(
    'BREVO_SENDER_EMAIL', os.environ.get('SMTP_FROM', '')).strip()
  brevo_sender_name = os.environ.get(
    'BREVO_SENDER_NAME', 'Smart Irrigation').strip()

  if brevo_api_key:
    if not brevo_sender_email:
      return False

    response = requests.post(
      'https://api.brevo.com/v3/smtp/email',
      headers={
        'accept': 'application/json',
        'api-key': brevo_api_key,
        'content-type': 'application/json',
      },
      json={
        'sender': {
          'name': brevo_sender_name,
          'email': brevo_sender_email,
        },
        'to': [{'email': recipient}],
        'subject': 'Smart Irrigation Password Reset OTP',
        'textContent': (
          f'Your Smart Irrigation password reset OTP is {otp}. '
          'This code expires in 10 minutes.'
        ),
      },
      timeout=20,
    )
    response.raise_for_status()
    return True

  smtp_host = os.environ.get('SMTP_HOST', 'smtp.gmail.com')
  smtp_port = int(os.environ.get('SMTP_PORT', '587'))
  smtp_user = os.environ.get('SMTP_USER', '')
  smtp_password = os.environ.get('SMTP_PASSWORD', '')
  smtp_from = os.environ.get('SMTP_FROM', smtp_user)

  if not smtp_host or not smtp_user or not smtp_password:
    return False

  message = EmailMessage()
  message['Subject'] = 'Smart Irrigation Password Reset OTP'
  message['From'] = smtp_from
  message['To'] = recipient
  message.set_content(
      f'Your Smart Irrigation password reset OTP is {otp}. '
      f'This code expires in 10 minutes.'
  )

  with smtplib.SMTP(smtp_host, smtp_port, timeout=15) as server:
    server.starttls()
    server.login(smtp_user, smtp_password)
    server.send_message(message)

  return True


def _otp_key(role, identifier):
  return f'{role}:{identifier.strip().lower()}'


def _request_password_otp(role):
  data = request.get_json(force=True)
  identifier = (data.get('email') or data.get('username') or '').strip()

  if not identifier:
    return jsonify({'error': 'Email is required'}), 400

  username, user = _find_user(identifier)
  if not user:
    return jsonify({'error': 'User not found'}), 404

  if role != 'any' and user.get('role') != role:
    return jsonify({'error': 'User not found for this role'}), 404

  recipient = str(user.get('email') or identifier).strip()
  if '@' not in recipient:
    return jsonify({'error': 'No email address is registered for this account'}), 400

  otp = f'{random.randint(100000, 999999)}'

  try:
    email_sent = _send_reset_otp_email(recipient, otp)
  except Exception as e:
    print('Failed to send OTP email:', e)
    return jsonify({'error': 'Could not send the verification email. Please try again.'}), 502

  if not email_sent:
    return jsonify({
      'error': 'Email delivery is not configured. Configure the SMTP settings and try again.'
    }), 503

  password_reset_otps[_otp_key(role, username)] = {
    'otp': otp,
    'expires_at': time.time() + OTP_EXPIRY_SECONDS,
    'verified': False
  }
  return jsonify({'message': 'Verification code sent to your registered email.'}), 200


def _validate_password_otp(role):
  data = request.get_json(force=True)
  identifier = (data.get('email') or data.get('username') or '').strip()
  otp = (data.get('otp') or '').strip()
  username, user = _find_user(identifier)

  if not user:
    return jsonify({'error': 'User not found'}), 404

  record = password_reset_otps.get(_otp_key(role, username))
  if not record:
    return jsonify({'error': 'OTP not found. Please request a new OTP'}), 400

  if time.time() > record['expires_at']:
    password_reset_otps.pop(_otp_key(role, username), None)
    return jsonify({'error': 'OTP expired. Please request a new OTP'}), 400

  if record['otp'] != otp:
    return jsonify({'error': 'Invalid OTP'}), 400

  record['verified'] = True
  return jsonify({'message': 'OTP verified'}), 200


def _reset_user_password(role):
  data = request.get_json(force=True)
  identifier = (data.get('email') or data.get('username') or '').strip()
  otp = (data.get('otp') or '').strip()
  new_password = (data.get('new_password') or '').strip()
  username, user = _find_user(identifier)

  if not user:
    return jsonify({'error': 'User not found'}), 404

  if not new_password:
    return jsonify({'error': 'New password is required'}), 400

  key = _otp_key(role, username)
  record = password_reset_otps.get(key)
  if not record:
    return jsonify({'error': 'Please verify OTP before resetting password'}), 400

  if time.time() > record['expires_at']:
    password_reset_otps.pop(key, None)
    return jsonify({'error': 'OTP expired. Please request a new OTP'}), 400

  if not record.get('verified') or record.get('otp') != otp:
    return jsonify({'error': 'Please verify the correct OTP first'}), 400

  new_password_hash = generate_password_hash(new_password)

  persisted = _persist_password_hash(username, user, new_password_hash)
  if not persisted and not LOCAL_JSON_WRITES_ENABLED:
    return jsonify({
      'error': 'Could not save the new password. Please try again.'
    }), 503

  target_id = user.get('id')
  target_email = (user.get('email') or identifier).strip().lower()
  for cached_user in users.values():
    cached_email = str(cached_user.get('email') or '').strip().lower()
    if (
        cached_user is user
        or (target_id is not None and cached_user.get('id') == target_id)
        or (target_email and cached_email == target_email)
    ):
      cached_user['password_hash'] = new_password_hash

  _write_users_file(users)
  password_reset_otps.pop(key, None)

  return jsonify({'message': 'Password reset successful'}), 200

# OpenWeatherMap API Key (Set OPENWEATHER_API_KEY env var in production)
OPENWEATHER_API_KEY = os.getenv("OPENWEATHER_API_KEY", "")
LATITUDE = 8.3114
LONGITUDE = 80.4037
_previous_day_rainfall_cache = {'date': None, 'value': 0.0}


def get_weather_forecast():
  """OpenWeatherMap API forecast rainfall (mm)"""
  try:
    url = f'https://api.openweathermap.org/data/2.5/forecast?lat={LATITUDE}&lon={LONGITUDE}&appid={OPENWEATHER_API_KEY}&units=metric'
    response = requests.get(url, timeout=5)
    if response.status_code == 200:
      data = response.json()
      total_rain_mm = 0.0
      for item in data.get('list', [])[:8]:
        rain_info = item.get('rain', {})
        total_rain_mm += rain_info.get('3h', 0.0)
      return round(total_rain_mm, 2)
    else:
      print("Weather API Error:", response.status_code)
      return 0.0
  except Exception as e:
    print("Weather API Exception:", e)
    return 0.0


def get_previous_day_rainfall():
  """Previous calendar day's rainfall at Mahakandarawa (mm)."""
  previous_date = datetime.date.today() - datetime.timedelta(days=1)
  date_key = previous_date.isoformat()
  if _previous_day_rainfall_cache['date'] == date_key:
    return _previous_day_rainfall_cache['value']

  try:
    response = requests.get(
      'https://api.open-meteo.com/v1/forecast',
      params={
        'latitude': LATITUDE,
        'longitude': LONGITUDE,
        'daily': 'precipitation_sum',
        'timezone': 'Asia/Colombo',
        'start_date': date_key,
        'end_date': date_key,
      },
      timeout=2,
    )
    if response.status_code == 200:
      rainfall = response.json().get('daily', {}).get('precipitation_sum', [])
      if rainfall and rainfall[0] is not None:
        value = round(max(0.0, float(rainfall[0])), 2)
        _previous_day_rainfall_cache.update(date=date_key, value=value)
        return value
  except Exception as e:
    print("Previous-day rainfall API exception:", e)
  _previous_day_rainfall_cache.update(date=date_key, value=0.0)
  return 0.0


# ---------------------------------------------------------------------------
# Real-time Arduino Uno Serial Telemetry
# ---------------------------------------------------------------------------
import threading
import re

latest_sensor_data = {
  'moisture': 68,
  'temperature': 30.0,
  'raw_analog': 450,
  'status': 'Searching for Arduino COM Port...',
  'connected': False,
  'com_port': None
}

def _arduino_serial_loop():
  global latest_sensor_data
  try:
    import serial
    import serial.tools.list_ports
  except ImportError:
    latest_sensor_data['status'] = 'pyserial package missing'
    return

  while True:
    try:
      ports = serial.tools.list_ports.comports()
      if not ports:
        latest_sensor_data['status'] = 'Arduino Disconnected (Plug in USB)'
        latest_sensor_data['connected'] = False
        time.sleep(2)
        continue

      target_port = None
      for p in ports:
        target_port = p.device
        break

      if not target_port:
        time.sleep(2)
        continue

      latest_sensor_data['status'] = f'Connecting to {target_port}...'
      latest_sensor_data['com_port'] = target_port

      with serial.Serial(target_port, 9600, timeout=2) as ser:
        latest_sensor_data['status'] = f'Arduino Connected ({target_port})'
        latest_sensor_data['connected'] = True
        time.sleep(1)

        while True:
          line = ser.readline().decode('utf-8', errors='ignore').strip()
          if line:
            raw_match = re.search(r'Raw_Analog:\s*(\d+)', line)
            moist_match = re.search(r'Moisture_Percent:\s*(\d+)', line)
            temp_match = re.search(r'Temperature_C:\s*([\d\.]+)', line)

            if moist_match or temp_match or raw_match:
              if raw_match:
                latest_sensor_data['raw_analog'] = int(raw_match.group(1))
              if moist_match:
                latest_sensor_data['moisture'] = int(moist_match.group(1))
              if temp_match:
                latest_sensor_data['temperature'] = float(temp_match.group(1))

              latest_sensor_data['connected'] = True
              latest_sensor_data['status'] = f'Arduino Live ({target_port})'
    except PermissionError:
      latest_sensor_data['status'] = f'{target_port} Busy (Close Arduino Serial Monitor)'
      latest_sensor_data['connected'] = False
      time.sleep(2)
    except Exception as e:
      err_str = str(e)
      if 'Access is denied' in err_str or 'PermissionError' in err_str:
        latest_sensor_data['status'] = f'{target_port} Busy (Close Arduino Serial Monitor)'
      else:
        latest_sensor_data['status'] = 'Arduino Disconnected'
      latest_sensor_data['connected'] = False
      time.sleep(2)


# Start the legacy Arduino Uno serial reader unless the deployment uses the
# ESP32 Wi-Fi client. In ESP32 mode, leaving this reader enabled would seize
# the board's COM port and prevent uploads or use of Arduino Serial Monitor.
_serial_reader_default = '0' if IS_RAILWAY else '1'
_serial_reader_enabled = os.getenv(
  'ENABLE_ARDUINO_SERIAL_READER', _serial_reader_default
).strip().lower() not in {
  '0', 'false', 'no', 'off'
}
if _serial_reader_enabled:
  _serial_thread = threading.Thread(target=_arduino_serial_loop, daemon=True)
  _serial_thread.start()
else:
  latest_sensor_data['status'] = 'ESP32 Wi-Fi telemetry mode'


@app.route('/sensor-data', methods=['GET'])
def get_sensor_data():
  return jsonify(latest_sensor_data), 200


@app.route('/sensor-data', methods=['POST'])
def update_sensor_data():
  data = request.get_json(silent=True)
  if not isinstance(data, dict):
    return jsonify({'status': 'error', 'message': 'JSON object required'}), 400
  device_id = data.get('deviceId')
  device_token = data.get('deviceToken')
  if not isinstance(device_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{3,80}', device_id):
    return jsonify({'status': 'error', 'message': 'Valid deviceId required'}), 400
  if not isinstance(device_token, str) or not device_token:
    return jsonify({'status': 'error', 'message': 'deviceToken required'}), 400
  moisture = data.get('moisture')
  temperature = data.get('temperature')
  if (isinstance(moisture, bool) or not isinstance(moisture, (int, float))
      or not math.isfinite(moisture) or not 0 <= moisture <= 100):
    return jsonify({'status': 'error', 'message': 'moisture must be a number from 0 to 100'}), 400
  if (isinstance(temperature, bool) or not isinstance(temperature, (int, float))
      or not math.isfinite(temperature) or not -40 <= temperature <= 85):
    return jsonify({'status': 'error', 'message': 'temperature must be a number from -40 to 85 C'}), 400
  conn = get_db_connection()
  if not conn:
    return jsonify({'status': 'error', 'message': 'IoT database unavailable'}), 503
  try:
    iot_store.record_reading(conn, device_id, device_token, moisture, temperature)
    return jsonify({'status': 'success', 'message': 'Sensor data recorded',
                    'deviceId': device_id, 'moisture': moisture,
                    'temperature': temperature}), 201
  except iot_store.UnknownDevice:
    return jsonify({'status': 'error', 'message': 'Unknown or disabled device'}), 404
  except iot_store.InvalidDeviceToken:
    return jsonify({'status': 'error', 'message': 'Invalid device token'}), 401
  except Exception as e:
    print('IoT sensor write error:', e)
    return jsonify({'status': 'error', 'message': 'IoT database unavailable'}), 503
  finally:
    conn.close()


@app.route('/api/user/sensor-data', methods=['GET'])
def get_user_sensor_data():
  farmer_id = _current_farmer_id()
  if farmer_id is None:
    return jsonify({'status': 'error', 'message': 'Farmer session required'}), 401
  conn = get_db_connection()
  if not conn:
    return jsonify({'status': 'error', 'message': 'IoT database unavailable'}), 503
  try:
    devices = iot_store.list_latest(conn, IOT_OFFLINE_SECONDS, farmer_id)
    if not devices:
      return jsonify({'status': 'no_device', 'message': 'No ESP32 registered for this user',
                      'devices': []}), 200
    latest = max(devices, key=lambda d: d['lastSeen'] or '')
    return jsonify({'status': 'success', **latest, 'devices': devices}), 200
  except Exception as e:
    print('IoT user read error:', e)
    return jsonify({'status': 'error', 'message': 'IoT database unavailable'}), 503
  finally:
    conn.close()


@app.route('/api/admin/sensors', methods=['GET'])
def get_admin_sensors():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  conn = get_db_connection()
  if not conn:
    return jsonify({'status': 'error', 'message': 'IoT database unavailable'}), 503
  try:
    sensors = iot_store.list_latest(conn, IOT_OFFLINE_SECONDS)
    for sensor in sensors:
      farmer = next((u for u in users.values()
                     if u.get('id') == sensor['farmerId'] and u.get('role') == 'farmer'), None)
      sensor['farmerName'] = farmer.get('name', farmer.get('email', '')) if farmer else f"Farmer #{sensor['farmerId']}"
    return jsonify({'status': 'success', 'sensors': sensors}), 200
  except Exception as e:
    print('IoT admin read error:', e)
    return jsonify({'status': 'error', 'message': 'IoT database unavailable'}), 503
  finally:
    conn.close()


@app.route('/api/sensor-history/<device_id>', methods=['GET'])
def get_sensor_history(device_id):
  farmer_id = _current_farmer_id()
  if not _admin_key_valid(request) and farmer_id is None:
    return jsonify({'status': 'error', 'message': 'Authorization required'}), 401
  try:
    limit = int(request.args.get('limit', '100'))
  except ValueError:
    return jsonify({'status': 'error', 'message': 'Invalid limit'}), 400
  if limit < 1 or limit > 500:
    return jsonify({'status': 'error', 'message': 'limit must be 1 to 500'}), 400
  conn = get_db_connection()
  if not conn:
    return jsonify({'status': 'error', 'message': 'IoT database unavailable'}), 503
  try:
    readings = iot_store.history(
      conn, device_id, limit, None if _admin_key_valid(request) else farmer_id)
    return jsonify({'status': 'success', 'deviceId': device_id,
                    'readings': readings}), 200
  except iot_store.UnknownDevice:
    return jsonify({'status': 'error', 'message': 'Device not found'}), 404
  except Exception as e:
    print('IoT history error:', e)
    return jsonify({'status': 'error', 'message': 'IoT database unavailable'}), 503
  finally:
    conn.close()


# Simple in-memory reservoir status (level in percent)
reservoir_status = {
  'level': 14.5,
  'source': 'sensor'
}


@app.route('/reservoir-status', methods=['GET'])
def get_reservoir_status():
  return jsonify({
    'level': reservoir_status.get('level'),
    'source': reservoir_status.get('source')
  }), 200


@app.route('/reservoir-status', methods=['POST'])
def set_reservoir_status():
  try:
    data = request.get_json(force=True)
    level = data.get('level')
    source = data.get('source', 'manual')
    if level is None:
      return jsonify({'status': 'error', 'message': 'level required'}), 400
    try:
      lvl = float(level)
    except Exception:
      return jsonify({'status': 'error', 'message': 'invalid level'}), 400
    lvl = max(0.0, min(100.0, lvl))
    reservoir_status['level'] = round(lvl, 2)
    reservoir_status['source'] = source
    return jsonify({'status': 'success', 'level': reservoir_status['level'], 'source': reservoir_status['source']}), 200
  except Exception as e:
    return jsonify({'status': 'error', 'message': str(e)}), 500


# --- User management / auth endpoints ---
def _admin_key_valid(req):
  key = req.headers.get('X-Admin-Key') or req.args.get('admin_key')
  if key == ADMIN_KEY:
    return True

  # Mobile admins authenticate through /login. Accept that signed session for
  # admin endpoints so the production ADMIN_KEY never has to be embedded in
  # the APK.
  authorization = req.headers.get('Authorization', '')
  if not authorization.startswith('Bearer '):
    return False
  try:
    payload = session_signer.loads(
      authorization[7:], max_age=SESSION_MAX_AGE_SECONDS)
  except (BadSignature, SignatureExpired):
    return False

  username = payload.get('username')
  user = users.get(username)
  return bool(
    payload.get('role') == 'admin'
    and user
    and user.get('role') == 'admin'
  )


@app.route('/admin/create-officer', methods=['POST'])
def admin_create_officer():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  data = request.get_json(force=True)
  username = data.get('username')
  password = data.get('password')
  if not username or not password:
    return jsonify({'status': 'error', 'message': 'username and password required'}), 400
  if username in users:
    return jsonify({'status': 'error', 'message': 'user already exists'}), 400
  users[username] = {
    'password_hash': generate_password_hash(password),
    'role': 'officer'
  }
  _write_users_file(users)
  return jsonify({'status': 'success', 'username': username, 'role': 'officer'}), 200


@app.route('/admin/create-user', methods=['POST'])
def admin_create_user():
  """Create a user with any role (admin, officer, farmer). Requires admin key."""
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  data = request.get_json(force=True)
  username = (data.get('username') or '').strip()
  password = (data.get('password') or '').strip()
  role = (data.get('role') or 'farmer').strip().lower()

  if not username or not password:
    return jsonify({'status': 'error', 'message': 'username and password required'}), 400
  if role not in ('admin', 'officer', 'farmer'):
    return jsonify({'status': 'error', 'message': 'role must be admin, officer, or farmer'}), 400
  normalized_username = username.lower()
  if normalized_username in users:
    return jsonify({'status': 'error', 'message': f'User "{username}" already exists'}), 400

  existing_ids = [
    account.get('id') for account in users.values()
    if isinstance(account.get('id'), int)
  ]
  account_id = max(existing_ids, default=0) + 1
  password_hash = generate_password_hash(password)
  email = normalized_username if '@' in normalized_username else None

  conn = get_db_connection()
  if conn is None:
    return jsonify({
      'status': 'error',
      'message': 'Database connection failed. Configure MYSQL_USER and MYSQL_PASSWORD.'
    }), 503

  cursor = None
  try:
    cursor = conn.cursor()
    _ensure_users_table(cursor)
    _upsert_mysql_user(
      cursor, account_id, normalized_username, email, password_hash,
      '', '', role,
    )
    conn.commit()
  except Exception as e:
    print('MySQL user insert error:', e)
    try:
      conn.rollback()
    except Exception:
      pass
    return jsonify({'status': 'error', 'message': 'Could not save the user in MySQL.'}), 500
  finally:
    if cursor is not None:
      cursor.close()
    conn.close()

  users[normalized_username] = {
    'id': account_id,
    'password_hash': password_hash,
    'role': role,
    'email': email,
    'name': username,
  }
  _audit('USER_CREATED', 'admin', f'Created user "{normalized_username}" with role "{role}"')
  _write_users_file(users)
  return jsonify({
    'status': 'success',
    'username': normalized_username,
    'role': role,
    'user_id': account_id,
  }), 200


def _generate_next_farmer_id():
  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor()
      cursor.execute("SELECT MAX(FarmerID) FROM farmer WHERE FarmerID < 10000")
      res = cursor.fetchone()
      max_id = res[0] if res and res[0] is not None else 0
      cursor.close()
      conn.close()
      return max_id + 1
    except Exception as e:
      print("Error generating next farmer_id:", e)
  small_ids = [u.get('id', 0) for u in users.values() if isinstance(u.get('id'), int) and u.get('id') < 10000]
  return max(small_ids, default=0) + 1


USERS_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS users (
  UserID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  AccountID INT NULL,
  Username VARCHAR(100) NOT NULL,
  Email VARCHAR(255) NULL,
  PasswordHash VARCHAR(255) NOT NULL,
  FirstName VARCHAR(100) NOT NULL DEFAULT '',
  LastName VARCHAR(100) NOT NULL DEFAULT '',
  Role ENUM('admin', 'officer', 'farmer') NOT NULL DEFAULT 'farmer',
  CreatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UpdatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (UserID),
  UNIQUE KEY uq_users_username (Username),
  UNIQUE KEY uq_users_email (Email),
  INDEX idx_users_role (Role),
  INDEX idx_users_account (Role, AccountID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
"""


def _ensure_users_table(cursor):
  cursor.execute(USERS_TABLE_SQL)


def _persist_password_hash(login_name, account, password_hash):
  """Persist a password change to the durable MySQL authentication store."""
  conn = get_db_connection()
  if conn is None:
    return False

  cursor = None
  try:
    cursor = conn.cursor()
    _ensure_users_table(cursor)

    canonical_login = next(
      (key for key, record in users.items()
       if record is account and '@' not in key),
      login_name,
    ).strip().lower()
    email = str(account.get('email') or '').strip().lower()
    role = str(account.get('role') or 'farmer').strip().lower()
    full_name = str(account.get('name') or '').strip()
    name_parts = full_name.split(maxsplit=1)
    first_name = name_parts[0] if name_parts else ''
    last_name = name_parts[1] if len(name_parts) > 1 else ''

    _upsert_mysql_user(
      cursor, account.get('id'), canonical_login, email, password_hash,
      first_name, last_name, role,
    )

    if role == 'farmer':
      cursor.execute(
        "UPDATE farmer SET Password = %s "
        "WHERE FarmerID = %s OR LOWER(Email) = LOWER(%s)",
        (password_hash, account.get('id'), email),
      )

    conn.commit()
    return True
  except Exception as exc:
    print('MySQL Password Persistence Error:', exc)
    try:
      conn.rollback()
    except Exception:
      pass
    return False
  finally:
    if cursor is not None:
      cursor.close()
    conn.close()


def _upsert_mysql_user(cursor, account_id, username, email, password_hash,
                       first_name, last_name, role):
  cursor.execute(
    "INSERT INTO users "
    "(AccountID, Username, Email, PasswordHash, FirstName, LastName, Role) "
    "VALUES (%s, %s, %s, %s, %s, %s, %s) "
    "ON DUPLICATE KEY UPDATE AccountID = VALUES(AccountID), "
    "Email = VALUES(Email), PasswordHash = VALUES(PasswordHash), "
    "FirstName = VALUES(FirstName), LastName = VALUES(LastName), "
    "Role = VALUES(Role)",
    (account_id, username, email or None, password_hash,
     first_name, last_name, role),
  )


def _sync_cached_farmers_to_mysql():
  """Backfill JSON accounts into MySQL farmer and users tables."""
  conn = get_db_connection()
  if conn is None:
    return 0

  unique_accounts = {}
  for login_name, account in users.items():
    account_id = account.get('id')
    email = str(account.get('email') or '').strip().lower()
    role = str(account.get('role') or 'farmer').lower()
    identity = (role, account_id, email or login_name.lower())
    username = login_name.strip().lower()
    existing = unique_accounts.get(identity)
    if existing is None or ('@' in existing[0] and '@' not in username):
      unique_accounts[identity] = (username, account)

  cursor = None
  try:
    cursor = conn.cursor()
    _ensure_users_table(cursor)
    for username, account in unique_accounts.values():
      account_id = account.get('id')
      email = str(account.get('email') or '').strip().lower()
      role = str(account.get('role') or 'farmer').lower()
      full_name = str(account.get('name') or '').strip()
      name_parts = full_name.split(maxsplit=1)
      first_name = name_parts[0] if name_parts else ''
      last_name = name_parts[1] if len(name_parts) > 1 else ''
      if role == 'farmer' and account_id is not None and email:
        cursor.execute(
          "INSERT INTO farmer (FarmerID, Email, Password, F_Name, L_Name) "
          "VALUES (%s, %s, %s, %s, %s) "
          "ON DUPLICATE KEY UPDATE Email = VALUES(Email), "
          "Password = VALUES(Password), F_Name = VALUES(F_Name), "
          "L_Name = VALUES(L_Name)",
          (int(account_id), email, account.get('password_hash'),
           first_name, last_name),
        )
      _upsert_mysql_user(
        cursor, account_id, username, email, account.get('password_hash', ''),
        first_name, last_name, role,
      )
    conn.commit()
    print(f'Synchronized {len(unique_accounts)} user account(s) to MySQL.')
    return len(unique_accounts)
  except Exception as e:
    print('MySQL farmer synchronization error:', e)
    try:
      conn.rollback()
    except Exception:
      pass
    return 0
  finally:
    if cursor is not None:
      cursor.close()
    conn.close()


def _load_users_from_mysql():
  """Replace the runtime authentication cache with persistent MySQL users."""
  conn = get_db_connection()
  if conn is None:
    return 0

  cursor = None
  try:
    cursor = conn.cursor(dictionary=True)
    _ensure_users_table(cursor)
    cursor.execute(
      "SELECT AccountID, Username, Email, PasswordHash, FirstName, "
      "LastName, Role FROM users ORDER BY UserID"
    )
    rows = cursor.fetchall()
    if not rows:
      return 0

    persistent_users = {}
    for row in rows:
      username = str(row.get('Username') or '').strip().lower()
      email = str(row.get('Email') or '').strip().lower()
      if not username and not email:
        continue
      first_name = str(row.get('FirstName') or '').strip()
      last_name = str(row.get('LastName') or '').strip()
      account = {
        'id': row.get('AccountID'),
        'password_hash': row.get('PasswordHash') or '',
        'role': str(row.get('Role') or 'farmer').lower(),
        'email': email or None,
        'name': f'{first_name} {last_name}'.strip() or username or email,
      }
      if username:
        persistent_users[username] = account
      if email:
        persistent_users[email] = account

    if persistent_users:
      users.clear()
      users.update(persistent_users)
    return len(rows)
  except Exception as exc:
    print('MySQL user cache load error:', exc)
    return 0
  finally:
    if cursor is not None:
      cursor.close()
    conn.close()


def initialize_persistent_users():
  """Create/sync the user table, then use MySQL as the runtime auth source."""
  _sync_cached_farmers_to_mysql()
  loaded = _load_users_from_mysql()
  print(f'Loaded {loaded} persistent user account(s) from MySQL.')
  return loaded


@app.route('/signup', methods=['POST'])
def farmer_signup():
  data = request.get_json(force=True)
  f_name = (data.get('f_name') or '').strip()
  l_name = (data.get('l_name') or '').strip()
  email = (data.get('email') or '').strip().lower()
  password = (data.get('password') or '').strip()

  if not email or not password:
    return jsonify({'status': 'error', 'error': 'Email and password required'}), 400

  username = email.split('@')[0] if '@' in email else email
  if email in users or username.lower() in users:
    return jsonify({'status': 'error', 'error': 'An account with this email already exists'}), 409

  new_id = _generate_next_farmer_id()
  password_hash = generate_password_hash(password)

  # Insert into MySQL farmer table
  conn = get_db_connection()
  if conn is None:
    return jsonify({
      'status': 'error',
      'error': 'Database connection failed. Configure MYSQL_USER and MYSQL_PASSWORD.'
    }), 503

  cursor = None
  try:
    cursor = conn.cursor()
    _ensure_users_table(cursor)
    conn.start_transaction()
    cursor.execute(
      "INSERT INTO farmer (FarmerID, Email, Password, F_Name, L_Name) VALUES (%s, %s, %s, %s, %s)",
      (new_id, email, password_hash, f_name, l_name)
    )
    _upsert_mysql_user(
      cursor, new_id, username.lower(), email, password_hash,
      f_name, l_name, 'farmer',
    )
    conn.commit()
  except Exception as e:
    print("MySQL Farmer Insert Error:", e)
    try:
      conn.rollback()
    except Exception:
      pass
    return jsonify({'status': 'error', 'error': 'Could not save the farmer account in MySQL.'}), 500
  finally:
    if cursor is not None:
      cursor.close()
    conn.close()

  print(f"Successfully inserted farmer #{new_id} ({email}) into MySQL database!")

  user_obj = {
    'id': new_id,
    'password_hash': password_hash,
    'role': 'farmer',
    'email': email,
    'name': f"{f_name} {l_name}".strip() or username
  }
  users[username.lower()] = user_obj
  users[email.lower()] = user_obj

  _write_users_file(users)
  _audit('USER_CREATED', 'self_signup', f'Registered farmer account "{username}" ({email})')
  return jsonify({'status': 'success', 'message': 'Account created successfully', 'farmer_id': new_id}), 201


@app.route('/change-password', methods=['POST'])
def change_password():
  data = request.get_json(force=True)
  username = (data.get('username') or '').strip()
  old_password = (data.get('old_password') or '').strip()
  new_password = (data.get('new_password') or '').strip()

  if not username or not old_password or not new_password:
    return jsonify({'status': 'error', 'message': 'All fields are required'}), 400

  user = users.get(username)
  matched_uname = username
  if not user:
    for u, info in users.items():
      if info.get('email') == username:
        user = info
        matched_uname = u
        break

  if not user or not check_password_hash(user.get('password_hash', ''), old_password):
    return jsonify({'status': 'error', 'message': 'Incorrect current password'}), 400

  new_password_hash = generate_password_hash(new_password)
  persisted = _persist_password_hash(matched_uname, user, new_password_hash)
  if not persisted and not LOCAL_JSON_WRITES_ENABLED:
    return jsonify({
      'status': 'error',
      'message': 'Could not save the new password. Please try again.'
    }), 503

  target_id = user.get('id')
  target_email = str(user.get('email') or username).strip().lower()
  for cached_user in users.values():
    cached_email = str(cached_user.get('email') or '').strip().lower()
    if (
        cached_user is user
        or (target_id is not None and cached_user.get('id') == target_id)
        or (target_email and cached_email == target_email)
    ):
      cached_user['password_hash'] = new_password_hash

  _write_users_file(users)
  _audit('PASSWORD_CHANGED', matched_uname, 'Updated account password')
  return jsonify({'status': 'success', 'message': 'Password updated successfully'}), 200


@app.route('/admin/users', methods=['GET'])
def admin_list_users():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  return jsonify({
    'status': 'success',
    'users': _unique_user_accounts(),
  }), 200


@app.route('/auth/login', methods=['POST'])
def auth_login():
  data = request.get_json(force=True)
  username = data.get('username')
  password = data.get('password')
  if not username or not password:
    return jsonify({'status': 'error', 'message': 'username and password required'}), 400
  matched_username, user = _find_user(username)
  if not user:
    return jsonify({'status': 'error', 'message': 'invalid credentials'}), 401
  if not check_password_hash(user['password_hash'], password):
    return jsonify({'status': 'error', 'message': 'invalid credentials'}), 401
  # For simplicity return role. In production return a JWT or session cookie.
  _audit('USER_LOGIN', matched_username, f'Logged in via /auth/login (role: {user["role"]})')
  return jsonify({'status': 'success', 'username': matched_username, 'role': user['role'],
                  'farmer_id': user.get('id', 101),
                  'session_token': _session_token(matched_username, user)}), 200


@app.route('/login', methods=['POST'])
def app_login():
  data = request.get_json(force=True)
  email = data.get('email', '').strip().lower()
  password = data.get('password', '').strip()

  # ADMIN_PASSWORD is the production source of truth for the built-in admin.
  # Check it directly so a stale MySQL password hash cannot lock the admin out
  # after the Railway variable is changed and the service is redeployed.
  configured_admin_password = os.environ.get(
    'ADMIN_PASSWORD', DEFAULT_ADMIN_PASSWORD)
  if email == DEFAULT_ADMIN_USERNAME:
    if not secrets.compare_digest(password, configured_admin_password):
      return jsonify({'error': 'Invalid email or password'}), 401

    admin_user = users.get(DEFAULT_ADMIN_USERNAME)
    if not admin_user or admin_user.get('role') != 'admin':
      admin_user = {
        'id': 1,
        'password_hash': generate_password_hash(configured_admin_password),
        'role': 'admin',
        'name': 'Admin',
      }
      users[DEFAULT_ADMIN_USERNAME] = admin_user

    return jsonify({
      'status': 'success',
      'name': 'Admin',
      'role': 'admin',
      'farmer_id': admin_user.get('id', 1),
      'session_token': _session_token(DEFAULT_ADMIN_USERNAME, admin_user),
    }), 200

  user = users.get(email)
  if not user:
    for u, info in users.items():
      if info.get('email', '').lower() == email or u.lower() == email:
        user = info
        break

  if user and check_password_hash(user.get('password_hash', ''), password):
    farmer_id = user.get('id', 101)
    if user.get('role') == 'admin':
      return jsonify({
        'status': 'success',
        'name': 'Admin',
        'role': 'admin',
        'farmer_id': farmer_id,
        'session_token': _session_token(email, user)
      }), 200

    _audit('USER_LOGIN', email, f'Logged in via /login (role: {user.get("role")})')
    return jsonify({
      'status': 'success',
      'name': user.get('name', email),
      'email': user.get('email', email),
      'role': user.get('role', 'farmer'),
      'farmer_id': farmer_id,
      'session_token': _session_token(email, user)
    }), 200

  return jsonify({'error': 'Invalid email or password'}), 401


@app.route('/forgot-password', methods=['POST'])
def forgot_password():
  return _request_password_otp('any')


@app.route('/validate-otp', methods=['POST'])
def validate_otp():
  return _validate_password_otp('any')


@app.route('/reset-password', methods=['POST'])
def reset_password():
  return _reset_user_password('any')


@app.route('/forgot-password/officer', methods=['POST'])
def forgot_password_officer():
  return _request_password_otp('officer')


@app.route('/validate-otp/officer', methods=['POST'])
def validate_otp_officer():
  return _validate_password_otp('officer')


@app.route('/reset-password/officer', methods=['POST'])
def reset_password_officer():
  return _reset_user_password('officer')


def calculate_urgency_score(soil_moisture, temperature=29.5,
                            days_since_last_irrigation=10.0):
  """Urgency = 100 * (0.5Si + 0.3Ti + 0.2Di), clamped to 0..100."""
  soil_factor = (85.0 - float(soil_moisture)) / (85.0 - 40.0)
  temperature_factor = (float(temperature) - 25.0) / (30.0 - 25.0)
  irrigation_interval_factor = float(days_since_last_irrigation) / 10.0

  soil_factor = min(1.0, max(0.0, soil_factor))
  temperature_factor = min(1.0, max(0.0, temperature_factor))
  irrigation_interval_factor = min(1.0, max(0.0, irrigation_interval_factor))

  score = 100.0 * (
    (0.5 * soil_factor)
    + (0.3 * temperature_factor)
    + (0.2 * irrigation_interval_factor)
  )
  return round(score, 2)
def calculate_target_water_req(soil_moisture, temperature=29.5,
                               previous_day_rainfall=0.0, area_acres=1.0):
  """Formula 2: Vi = max(0, (85-Mi)+(Ti-25)-(R*0.1))*Ai*4047 litres."""
  adjusted_depth = (
    (85.0 - float(soil_moisture))
    + (float(temperature) - 25.0)
    - (float(previous_day_rainfall) * 0.1)
  )
  target_liters = max(0.0, adjusted_depth) * max(0.0, float(area_acres)) * 4047.0
  return round(target_liters, 2)


@app.route('/priority-schedule', methods=['GET'])
def get_priority_schedule():
  forecast_rain = get_weather_forecast()
  previous_day_rainfall = get_previous_day_rainfall()
  reservoir_water_level = 14.5

  # Dynamic prediction release status evaluation
  predicted_release_val = 45.18
  if predicted_release_val > 150.0:
    release_status = 'High'
    allocation_policy = 'FULL_ALLOCATION'
    policy_description = 'High Water Supply (>150 Acft/Day): 🟢 Full Water Allocation to All Zones (Formula 2 Applied).'
  elif predicted_release_val >= 80.0:
    release_status = 'Medium'
    allocation_policy = 'ROUND_ROBIN'
    policy_description = 'Medium Water Supply (80-150 Acft/Day): 🟠 Round-Robin Rotational Allocation across Zones (Formula 2 Applied).'
  else:
    release_status = 'Low'
    allocation_policy = 'PRIORITY_BASED'
    policy_description = 'Low Water Supply (<80 Acft/Day): 🔴 Priority-Based Scarcity Allocation by Zone Urgency Score (Formula 1 & 2 Applied).'

  def _clean_zone(raw):
    raw_str = str(raw or '').strip()
    if '(' in raw_str:
      part = raw_str.split('(')[0].strip()
      if part:
        return part
    return raw_str or 'Zone 1'

  last_irrigation_by_field = {}
  for historical_request in water_requests:
    if str(historical_request.get('Status', '')).lower() != 'approved':
      continue
    try:
      field_key = (
        int(historical_request.get('farmer_id')),
        int(historical_request.get('FieldID')),
      )
      irrigation_time = datetime.datetime.fromisoformat(
        str(historical_request.get('RequestTime')),
      )
      previous_time = last_irrigation_by_field.get(field_key)
      if previous_time is None or irrigation_time > previous_time:
        last_irrigation_by_field[field_key] = irrigation_time
    except (TypeError, ValueError):
      continue

  zone_groups = {}
  for req in water_requests:
    z_name = _clean_zone(req.get('ZoneName'))
    if z_name not in zone_groups:
      zone_groups[z_name] = {
          'ZoneName': z_name,
          'moistures': [],
          'temps': [],
          'areas': [],
          'irrigation_intervals': [],
          'count': 0,
      }

    moist = req.get('SoilMoisture') or req.get('soil_moisture')
    if moist is None:
      moist = ((req.get('RequestID', 1) * 17) % 35 + 18)

    temp = req.get('SoilTemperature') or req.get('soil_temperature')
    if temp is None:
      temp = (28.0 + (req.get('RequestID', 1) % 5) * 0.7)

    area_acres = req.get('AreaAcres') or req.get('Size')
    if area_acres is None:
      try:
        request_farmer_id = int(req.get('farmer_id'))
        request_field_id = int(req.get('FieldID'))
        matching_field = next(
          (
            field for field in farmer_fields.get(request_farmer_id, [])
            if int(field.get('FieldID', -1)) == request_field_id
          ),
          None,
        )
        area_acres = matching_field.get('Size', 2.5) if matching_field else 2.5
      except (TypeError, ValueError):
        area_acres = 2.5

    days_since_last_irrigation = req.get('DaysSinceLastIrrigation')
    if days_since_last_irrigation is None:
      try:
        field_key = (int(req.get('farmer_id')), int(req.get('FieldID')))
        last_irrigation = last_irrigation_by_field.get(field_key)
        days_since_last_irrigation = (
          max(
            0.0,
            (datetime.datetime.now() - last_irrigation).total_seconds() / 86400.0,
          )
          if last_irrigation is not None
          else 10.0
        )
      except (TypeError, ValueError):
        days_since_last_irrigation = 10.0

    zone_groups[z_name]['moistures'].append(float(moist))
    zone_groups[z_name]['temps'].append(float(temp))
    zone_groups[z_name]['areas'].append(float(area_acres))
    zone_groups[z_name]['irrigation_intervals'].append(
      float(days_since_last_irrigation),
    )
    zone_groups[z_name]['count'] += 1

  zones_sensor_data = []
  if zone_groups:
    for z_name, data in zone_groups.items():
      moist_list = data['moistures']
      temp_list = data['temps']
      z_count = data['count']

      z_weight = 1.5 if 'tail' in z_name.lower() or '3' in z_name else (1.2 if 'middle' in z_name.lower() or '2' in z_name else 1.0)
      total_acres = round(sum(data['areas']), 1)

      zones_sensor_data.append({
          'ZoneID': f'Z_{hash(z_name) % 1000}',
          'ZoneName': z_name,
          'ZoneWeight': z_weight,
          'TotalFields': z_count,
          'TotalAreaAcres': total_acres,
          'FieldMoistureReadings': moist_list,
          'FieldTempReadings': temp_list,
          'DaysSinceLastIrrigation': data['irrigation_intervals'],
          'RoundRobinStatus': 'Active Rotation',
      })

    # Demo zones keep the priority screen populated for presentations while
    # preserving any real zones built from farmer requests above.
    demo_zones = [
        {
            'ZoneID': 'DEMO_Z_2',
            'ZoneName': 'Zone 2',
            'ZoneWeight': 1.3,
            'TotalFields': 2,
            'TotalAreaAcres': 8.0,
            'FieldMoistureReadings': [24.0, 29.0],
            'FieldTempReadings': [34.2, 33.5],
            'DaysSinceLastIrrigation': [9.0, 8.0],
            'RoundRobinStatus': 'Demo - High Priority',
        },
        {
            'ZoneID': 'DEMO_Z_3',
            'ZoneName': 'Zone 3',
            'ZoneWeight': 1.1,
            'TotalFields': 3,
            'TotalAreaAcres': 15.0,
            'FieldMoistureReadings': [48.0, 52.0, 55.0],
            'FieldTempReadings': [29.0, 30.0, 28.5],
            'DaysSinceLastIrrigation': [5.0, 4.0, 6.0],
            'RoundRobinStatus': 'Demo - Medium Priority',
        },
        {
            'ZoneID': 'DEMO_Z_4',
            'ZoneName': 'Zone 4',
            'ZoneWeight': 1.0,
            'TotalFields': 2,
            'TotalAreaAcres': 6.0,
            'FieldMoistureReadings': [70.0, 74.0],
            'FieldTempReadings': [26.2, 27.0],
            'DaysSinceLastIrrigation': [2.0, 3.0],
            'RoundRobinStatus': 'Demo - Low Priority',
        },
    ]
    existing_zone_names = {
      _clean_zone(zone['ZoneName']).lower() for zone in zones_sensor_data
    }
    zones_sensor_data.extend(
      zone for zone in demo_zones
      if _clean_zone(zone['ZoneName']).lower() not in existing_zone_names
    )

  if not zones_sensor_data:
    zones_sensor_data = [
        {
            'ZoneID': 'Z_101',
            'ZoneName': 'Zone 3 (Field #15)',
            'ZoneWeight': 1.5,
            'TotalFields': 1,
            'TotalAreaAcres': 2.5,
            'FieldMoistureReadings': [28.0],
            'FieldTempReadings': [28.0],
            'DaysSinceLastIrrigation': [10.0],
            'RoundRobinStatus': 'Active (Rotation 1)',
        },
        {
            'ZoneID': 'Z_102',
            'ZoneName': 'Zone 28 (Field #14, #103)',
            'ZoneWeight': 1.4,
            'TotalFields': 3,
            'TotalAreaAcres': 7.5,
            'FieldMoistureReadings': [45.0, 46.0, 34.0],
            'FieldTempReadings': [28.7, 30.8, 30.1],
            'DaysSinceLastIrrigation': [8.0, 7.0, 10.0],
            'RoundRobinStatus': 'Queued (Rotation 2)',
        },
        {
            'ZoneID': 'Z_103',
            'ZoneName': 'Zone 5 (Field #101)',
            'ZoneWeight': 1.1,
            'TotalFields': 1,
            'TotalAreaAcres': 2.5,
            'FieldMoistureReadings': [35.0],
            'FieldTempReadings': [28.7],
            'DaysSinceLastIrrigation': [9.0],
            'RoundRobinStatus': 'Queued (Rotation 3)',
        },
        {
            'ZoneID': 'Z_104',
            'ZoneName': 'Zone 9 (Field #102)',
            'ZoneWeight': 1.2,
            'TotalFields': 1,
            'TotalAreaAcres': 2.5,
            'FieldMoistureReadings': [52.0],
            'FieldTempReadings': [29.4],
            'DaysSinceLastIrrigation': [6.0],
            'RoundRobinStatus': 'Queued (Rotation 4)',
        },
    ]

  schedule = []
  for z in zones_sensor_data:
    moist_list = z['FieldMoistureReadings']
    temp_list = z['FieldTempReadings']
    irrigation_intervals = z['DaysSinceLastIrrigation']

    avg_moisture = round(sum(moist_list) / len(moist_list), 1)
    avg_temp = round(sum(temp_list) / len(temp_list), 1)
    avg_days_since_last_irrigation = round(
      sum(irrigation_intervals) / len(irrigation_intervals),
      1,
    )

    zone_urgency_score = calculate_urgency_score(
      avg_moisture,
      avg_temp,
      avg_days_since_last_irrigation,
    )
    zone_target_water_liters = calculate_target_water_req(
      avg_moisture,
      avg_temp,
      previous_day_rainfall,
      z['TotalAreaAcres'],
    )
    zone_total_liters = int(round(zone_target_water_liters))

    schedule.append({
        'ZoneID': z['ZoneID'],
        'ZoneName': z['ZoneName'],
        'ZoneWeight': z['ZoneWeight'],
        'TotalFields': z['TotalFields'],
        'TotalAreaAcres': z['TotalAreaAcres'],
        'AvgSoilMoisture': avg_moisture,
        'AvgSoilTemp': avg_temp,
        'AvgDaysSinceLastIrrigation': avg_days_since_last_irrigation,
        'urgency_score': zone_urgency_score,
        'target_water_req_liters': zone_total_liters,
        'PredictedVolume': zone_total_liters,
        'RainfallForecast': forecast_rain,
        'PreviousDayRainfall': previous_day_rainfall,
        'WaterLevel': f'{reservoir_water_level} ft',
        'RoundRobinStatus': z['RoundRobinStatus'],
        'Date': 'Today',
        'Explanation': (
            f'[{release_status} Supply Policy] Avg Moisture: {avg_moisture}%, Avg Temp: {avg_temp}°C, '
            f'Avg Days Since Irrigation: {avg_days_since_last_irrigation}. '
            f'Previous-day Rainfall: {previous_day_rainfall} mm, Area: {z["TotalAreaAcres"]} acres. '
            f'Urgency Score: {zone_urgency_score} (Formula 1). Target Water Needed: {zone_total_liters} L (Formula 2).'
        ),
    })

  if release_status == 'Low':
    sorted_schedule = sorted(schedule, key=lambda x: x['urgency_score'], reverse=True)
  elif release_status == 'Medium':
    sorted_schedule = schedule
  else:
    sorted_schedule = sorted(schedule, key=lambda x: x['target_water_req_liters'], reverse=True)

  for index, item in enumerate(sorted_schedule):
    item['Rank'] = index + 1

  return jsonify({
      'status': 'success',
      'release_status': release_status,
      'allocation_policy': allocation_policy,
      'policy_description': policy_description,
      'schedule': sorted_schedule
  }), 200


@app.route('/routes', methods=['GET'])
def list_routes():
  rules = []
  for rule in app.url_map.iter_rules():
    rules.append({'endpoint': rule.endpoint, 'rule': str(rule), 'methods': list(rule.methods)})
  return jsonify({'routes': rules}), 200


@app.route('/health', methods=['GET'])
def health_check():
  """Lightweight Railway health check without exposing configuration values."""
  conn = get_db_connection()
  database_ready = conn is not None
  if conn is not None:
    conn.close()
  return jsonify({
    'status': 'ok' if database_ready else 'degraded',
    'database': 'connected' if database_ready else 'unavailable',
    'model_loaded': water_release_model is not None,
    'admin_session_auth': True,
    'admin_login_source': 'environment',
    'request_timezone': str(APP_TIMEZONE),
  }), 200 if database_ready else 503


# ---------------------------------------------------------------------------
# Farmer Fields endpoints (MySQL DB Integrated)
# ---------------------------------------------------------------------------
@app.route('/fields/<int:farmer_id>', methods=['GET'])
def get_farmer_fields(farmer_id):
  db_fields = []
  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor(dictionary=True)
      cursor.execute("SELECT FieldID, FarmerID, ZoneNo, Size FROM field_profile WHERE FarmerID = %s", (farmer_id,))
      rows = cursor.fetchall()
      for r in rows:
        db_fields.append({
          'FieldID': r['FieldID'],
          'FarmerID': r['FarmerID'],
          'ZoneNo': r['ZoneNo'],
          'Size': float(r['Size']) if r['Size'] else 1.0,
          'CropType': 'General',
          'Moisture': f'{random.randint(40, 80)}%',
          'Status': 'Optimal' if random.random() > 0.3 else 'Needs Water'
        })
      cursor.close()
      conn.close()
    except Exception as e:
      print("Error reading fields from MySQL:", e)

  file_fields = farmer_fields.get(farmer_id, [])
  field_map = {f['FieldID']: f for f in file_fields if 'FieldID' in f}
  for f in db_fields:
    field_map[f['FieldID']] = f

  return jsonify({'fields': list(field_map.values())}), 200


@app.route('/fields/<int:farmer_id>', methods=['POST'])
def add_farmer_field(farmer_id):
  data = request.get_json(force=True)
  zone_no = int(data.get('zone_no', 1))
  size = float(data.get('size', 1.0))
  crop_type = data.get('crop_type', 'General')

  new_id = None
  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor()
      cursor.execute(
        "INSERT INTO field_profile (FarmerID, ZoneNo, Size) VALUES (%s, %s, %s)",
        (farmer_id, zone_no, size)
      )
      new_id = cursor.lastrowid
      cursor.close()
      conn.close()
      print(f"Successfully inserted field profile #{new_id} for farmer {farmer_id} in MySQL database!")
    except Exception as e:
      print("Error inserting field into MySQL field_profile:", e)

  if not new_id:
    if farmer_id not in farmer_fields:
      farmer_fields[farmer_id] = []
    new_id = max([f['FieldID'] for f in farmer_fields[farmer_id]], default=100) + 1

  new_field = {
    'FieldID': new_id,
    'FarmerID': farmer_id,
    'ZoneNo': zone_no,
    'Size': size,
    'CropType': crop_type,
    'Moisture': f'{random.randint(30, 80)}%',
    'Status': 'Optimal' if random.random() > 0.3 else 'Needs Water',
  }

  if farmer_id not in farmer_fields:
    farmer_fields[farmer_id] = []
  farmer_fields[farmer_id].append(new_field)

  _audit('FIELD_CREATED', f'farmer_{farmer_id}', f'Registered field #{new_id} in Zone {zone_no} (MySQL field_profile synced)')
  _write_fields_file(farmer_fields)
  return jsonify({'status': 'success', 'field': new_field}), 201


# ---------------------------------------------------------------------------
# Water Request endpoints (MySQL DB Integrated)
# ---------------------------------------------------------------------------
def _validated_client_sensor_snapshot(data, expected_zone_no):
  """Validate a farmer dashboard reading before attaching it to a request."""
  snapshot = data.get('sensor_snapshot')
  if not isinstance(snapshot, dict):
    return None

  moisture = snapshot.get('moisture')
  temperature = snapshot.get('temperature')
  device_id = snapshot.get('device_id')
  recorded_at = snapshot.get('recorded_at')
  try:
    zone_no = int(snapshot.get('zone_no'))
  except (TypeError, ValueError):
    return None

  if zone_no != expected_zone_no:
    return None
  if (isinstance(moisture, bool) or not isinstance(moisture, (int, float))
      or not math.isfinite(moisture) or not 0 <= moisture <= 100):
    return None
  if (isinstance(temperature, bool) or not isinstance(temperature, (int, float))
      or not math.isfinite(temperature) or not -40 <= temperature <= 85):
    return None
  if not isinstance(device_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{3,80}', device_id):
    return None
  if recorded_at is not None:
    if not isinstance(recorded_at, str):
      return None
    try:
      datetime.datetime.fromisoformat(recorded_at.replace('Z', '+00:00'))
    except ValueError:
      return None

  return {
    'SoilMoisture': float(moisture),
    'SoilTemperature': float(temperature),
    'SensorRecordedAt': recorded_at,
    'DeviceID': device_id,
    'ZoneNo': zone_no,
    'SensorSource': 'supabase',
  }


@app.route('/request-water', methods=['POST'])
def submit_water_request():
  import datetime
  data = request.get_json(silent=True) or {}
  try:
    farmer_id = int(data.get('farmer_id'))
    field_id = int(data.get('field_id'))
    area_acres = float(data.get('area_acres', 2.5))
  except (TypeError, ValueError):
    return jsonify({'error': 'farmer_id and field_id are required'}), 400
  current_farmer = _current_farmer_id()
  if request.headers.get('Authorization') and current_farmer is None:
    return jsonify({'error': 'Valid farmer session required'}), 401
  if current_farmer is not None:
    farmer_id = current_farmer

  # Resolve the field before creating a request or attaching a zone reading.
  zone_no = None
  conn = get_db_connection()
  if conn is None:
    return jsonify({'error': 'Database connection failed. Request was not saved.'}), 503
  cursor = None
  try:
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT ZoneNo, Size FROM field_profile WHERE FieldID = %s AND FarmerID = %s",
                   (field_id, farmer_id))
    fp_row = cursor.fetchone()
    if fp_row:
      zone_no = int(fp_row['ZoneNo'])
      if fp_row.get('Size') is not None:
        area_acres = float(fp_row['Size'])
  except Exception as e:
    print('Field lookup error:', e)
    return jsonify({'error': 'Could not verify the field in the database.'}), 503
  finally:
    if cursor is not None:
      cursor.close()
    conn.close()
  if zone_no is None:
    for field in farmer_fields.get(farmer_id, []):
      if field.get('FieldID') == field_id:
        zone_no = int(field['ZoneNo'])
        area_acres = float(field.get('Size', area_acres))
        break
  if zone_no is None:
    return jsonify({'error': 'Field not found for farmer'}), 404
  zone_name = f'Zone {zone_no} (Field #{field_id})'

  conn = get_db_connection()
  if conn is None:
    return jsonify({'error': 'Database connection failed. Request was not saved.'}), 503
  cursor = None
  try:
    cursor = conn.cursor()
    cursor.execute(
      "INSERT INTO irrigation_request (FarmerID, FieldID, RequestTime, Status) VALUES (%s, %s, UTC_TIMESTAMP(), 'Pending')",
      (farmer_id, field_id)
    )
    new_req_id = cursor.lastrowid
    conn.commit()
    print(f"Successfully inserted irrigation request #{new_req_id} into MySQL database!")
  except Exception as e:
    print("Error inserting water request into MySQL:", e)
    try:
      conn.rollback()
    except Exception:
      pass
    return jsonify({'error': 'Could not save the water request in the database.'}), 500
  finally:
    if cursor is not None:
      cursor.close()
    conn.close()

  req = {
    'RequestID': new_req_id,
    'farmer_id': farmer_id,
    'FieldID': field_id,
    'ZoneName': zone_name,
    'Status': 'Pending',
    'RequestTime': _local_now().strftime('%Y-%m-%d %H:%M:%S'),
    'farmer_name': _farmer_display_name(farmer_id),
    'AreaAcres': area_acres,
    'ZoneNo': zone_no,
  }

  # Keep the reading at request time, independently of future live updates.
  if zone_no is not None and current_farmer is not None:
    conn = get_db_connection()
    if conn:
      try:
        reading = iot_store.latest_for_field(conn, farmer_id, zone_no, IOT_OFFLINE_SECONDS)
        if reading and reading['deviceStatus'] == 'ONLINE':
          iot_store.save_request_snapshot(conn, new_req_id, farmer_id, field_id, zone_no, reading)
          req.update({
            'SoilMoisture': reading['moisture'],
            'SoilTemperature': reading['temperature'],
            'SensorRecordedAt': reading['recordedAt'],
            'DeviceID': reading['deviceId'],
            'ZoneNo': zone_no,
          })
      except Exception as e:
        print('Sensor snapshot write error:', e)
      finally:
        conn.close()

  # The Flutter dashboards use Supabase for live telemetry while this Flask
  # service may use a separate MySQL connection. If MySQL had no matching
  # reading, retain the authenticated farmer's validated Supabase reading that
  # accompanied the request.
  if req.get('SoilMoisture') is None and current_farmer is not None:
    client_snapshot = _validated_client_sensor_snapshot(data, zone_no)
    if client_snapshot:
      req.update(client_snapshot)

  water_requests.insert(0, req)  # newest first
  _audit('WATER_REQUEST', f'farmer_{farmer_id}', f'Submitted water request #{req["RequestID"]} for field #{field_id} ({zone_name})')
  _write_requests_file(water_requests)
  return jsonify({'status': 'success', 'request': req}), 201


@app.route('/my-requests/<int:farmer_id>', methods=['GET'])
def get_my_requests(farmer_id):
  import datetime
  db_reqs = []
  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor(dictionary=True)
      cursor.execute(
        "SELECT ir.RequestID, ir.FarmerID, ir.FieldID, ir.RequestTime, ir.Status, fp.ZoneNo "
        "FROM irrigation_request ir LEFT JOIN field_profile fp ON ir.FieldID = fp.FieldID "
        "WHERE ir.FarmerID = %s ORDER BY ir.RequestID DESC",
        (farmer_id,)
      )
      rows = cursor.fetchall()
      for r in rows:
        req_time_str = _format_utc_as_local(r['RequestTime'])
        db_reqs.append({
          'RequestID': r['RequestID'],
          'farmer_id': r['FarmerID'],
          'FieldID': r['FieldID'],
          'ZoneName': f"Zone {r.get('ZoneNo', '?')}",
          'Status': r['Status'],
          'RequestTime': req_time_str,
          'farmer_name': _farmer_display_name(r['FarmerID'])
        })
      cursor.close()
      conn.close()
    except Exception as e:
      print("Error reading requests from MySQL:", e)

  file_reqs = [r for r in water_requests if r.get('farmer_id') == farmer_id]
  req_map = {r['RequestID']: r for r in file_reqs if 'RequestID' in r}
  for r in db_reqs:
    req_map[r['RequestID']] = r

  sensor_fields = ('SoilMoisture', 'SoilTemperature', 'SensorRecordedAt',
                   'DeviceID')
  if _current_farmer_id() == farmer_id:
    combined_reqs = _attach_request_snapshots(list(req_map.values()))
  else:
    combined_reqs = [dict(item) for item in req_map.values()]
    for item in combined_reqs:
      for field in sensor_fields:
        item.pop(field, None)
  now = _local_now().replace(tzinfo=None)
  display_reqs = []
  for r in combined_reqs:
    display_req = dict(r)
    try:
      req_time = datetime.datetime.strptime(r['RequestTime'], '%Y-%m-%d %H:%M:%S')
      delta = now - req_time
      mins = int(delta.total_seconds() / 60)
      if mins < 1:
        display_req['RequestTime'] = 'Just now'
      elif mins < 60:
        display_req['RequestTime'] = f'{mins} mins ago'
      else:
        hrs = mins // 60
        display_req['RequestTime'] = f'{hrs} hour{"s" if hrs > 1 else ""} ago'
    except Exception:
      pass
    display_reqs.append(display_req)

  return jsonify({'requests': display_reqs}), 200


# Legacy endpoint for officer/irrigation screen
@app.route('/requests', methods=['GET'])
def get_all_requests():
  public_requests = []
  for item in water_requests:
    safe_item = {key: value for key, value in item.items()
                 if key not in ('SoilMoisture', 'SoilTemperature',
                                'SensorRecordedAt', 'DeviceID')}
    public_requests.append(safe_item)
  return jsonify({'requests': public_requests}), 200


# ---------------------------------------------------------------------------
# Admin Water Request Management
# ---------------------------------------------------------------------------
@app.route('/admin/water-requests', methods=['GET'])
def admin_get_water_requests():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  db_reqs = []
  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor(dictionary=True)
      cursor.execute(
        "SELECT ir.RequestID, ir.FarmerID, ir.FieldID, ir.RequestTime, ir.Status, f.F_Name, f.L_Name, fp.ZoneNo, fp.Size "
        "FROM irrigation_request ir "
        "LEFT JOIN farmer f ON ir.FarmerID = f.FarmerID "
        "LEFT JOIN field_profile fp ON ir.FieldID = fp.FieldID "
        "ORDER BY ir.RequestID DESC"
      )
      rows = cursor.fetchall()
      for r in rows:
        req_time_str = _format_utc_as_local(r['RequestTime'])
        database_name = (
          f"{r.get('F_Name', '')} {r.get('L_Name', '')}".strip()
        )
        farmer_name = _farmer_display_name(r['FarmerID'], database_name)
        db_reqs.append({
          'RequestID': r['RequestID'],
          'farmer_id': r['FarmerID'],
          'FieldID': r['FieldID'],
          'ZoneName': f"Zone {r.get('ZoneNo', '?')} (Field #{r['FieldID']})",
          'Status': r['Status'],
          'RequestTime': req_time_str,
          'farmer_name': farmer_name,
          'AreaAcres': float(r['Size']) if r.get('Size') is not None else 2.5,
        })
      cursor.close()
      conn.close()
    except Exception as e:
      print("Error reading admin water requests from MySQL:", e)

  req_map = {}
  for r in db_reqs:
    if 'RequestID' in r:
      req_map[r['RequestID']] = r
  for r in reversed(water_requests):
    if 'RequestID' in r:
      req_map[r['RequestID']] = r

  response_reqs = [dict(item) for item in req_map.values()]
  for item in response_reqs:
    farmer_id = item.get('farmer_id') or item.get('FarmerID')
    if farmer_id is not None:
      item['farmer_name'] = _farmer_display_name(
        farmer_id,
        item.get('farmer_name'),
      )
  sorted_reqs = sorted(_attach_request_snapshots(response_reqs),
                       key=lambda x: x.get('RequestID', 0), reverse=True)
  _attach_live_admin_sensor_values(sorted_reqs)
  previous_day_rainfall = get_previous_day_rainfall()
  for req in sorted_reqs:
    req.setdefault('PreviousDayRainfall', previous_day_rainfall)
    if req.get('AreaAcres') is None:
      req['AreaAcres'] = 2.5
      try:
        farmer_id = int(req.get('farmer_id'))
        field_id = int(req.get('FieldID'))
        for field in farmer_fields.get(farmer_id, []):
          if int(field.get('FieldID', -1)) == field_id:
            req['AreaAcres'] = float(field.get('Size', 2.5))
            break
      except (TypeError, ValueError):
        pass
  return jsonify({'status': 'success', 'requests': sorted_reqs}), 200


@app.route('/admin/water-requests/<int:req_id>/approve', methods=['POST'])
def admin_approve_request(req_id):
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401

  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor()
      cursor.execute("UPDATE irrigation_request SET Status = 'Approved' WHERE RequestID = %s", (req_id,))
      cursor.close()
      conn.close()
    except Exception as e:
      print("MySQL Update Error:", e)

  for r in water_requests:
    if r['RequestID'] == req_id:
      r['Status'] = 'Approved'
      _audit('REQUEST_APPROVED', 'admin', f'Approved water request #{req_id} for {r["ZoneName"]}')
      _write_requests_file(water_requests)
      return jsonify({'status': 'success', 'request': r}), 200
  return jsonify({'status': 'success'}), 200


@app.route('/admin/water-requests/<int:req_id>/reject', methods=['POST'])
def admin_reject_request(req_id):
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401

  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor()
      cursor.execute("UPDATE irrigation_request SET Status = 'Rejected' WHERE RequestID = %s", (req_id,))
      cursor.close()
      conn.close()
    except Exception as e:
      print("MySQL Update Error:", e)

  for r in water_requests:
    if r['RequestID'] == req_id:
      r['Status'] = 'Rejected'
      _audit('REQUEST_REJECTED', 'admin', f'Rejected water request #{req_id} for {r["ZoneName"]}')
      _write_requests_file(water_requests)
      return jsonify({'status': 'success', 'request': r}), 200
  return jsonify({'status': 'success'}), 200


@app.route('/admin/clear-requests', methods=['POST'])
def admin_clear_requests():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401

  conn = get_db_connection()
  if conn is None:
    return jsonify({
      'status': 'error',
      'message': 'Database connection failed. Requests were not cleared.'
    }), 503

  cursor = None
  try:
    cursor = conn.cursor()
    cursor.execute('DELETE FROM irrigation_request')
    deleted_count = cursor.rowcount
    conn.commit()
  except Exception as e:
    print('MySQL clear requests error:', e)
    try:
      conn.rollback()
    except Exception:
      pass
    return jsonify({
      'status': 'error',
      'message': 'Could not clear requests from the database.'
    }), 503
  finally:
    if cursor is not None:
      cursor.close()
    conn.close()

  global water_requests
  water_requests.clear()
  _write_requests_file(water_requests)
  _audit(
    'REQUESTS_CLEARED',
    'admin',
    f'Cleared {deleted_count} water request(s) from the table'
  )
  return jsonify({
    'status': 'success',
    'message': 'All requests cleared',
    'deleted_count': deleted_count
  }), 200


# ---------------------------------------------------------------------------
# Admin Stats & Audit Trail
# ---------------------------------------------------------------------------
@app.route('/admin/stats', methods=['GET'])
def admin_stats():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401

  conn = get_db_connection()
  db_reqs = []
  if conn:
    try:
      cursor = conn.cursor(dictionary=True)
      cursor.execute("SELECT RequestID, Status FROM irrigation_request")
      db_reqs = cursor.fetchall()
      cursor.close()
      conn.close()
    except Exception as e:
      print("MySQL stats error:", e)

  req_map = {r['RequestID']: r for r in water_requests if 'RequestID' in r}
  for r in db_reqs:
    req_map[r['RequestID']] = r

  all_reqs = list(req_map.values())
  unique_users = _unique_user_accounts()
  total_users = len(unique_users)
  total_requests = len(all_reqs)
  pending = sum(1 for r in all_reqs if r.get('Status') == 'Pending')
  approved = sum(1 for r in all_reqs if r.get('Status') == 'Approved')
  rejected = sum(1 for r in all_reqs if r.get('Status') == 'Rejected')
  farmers = sum(1 for u in unique_users if u.get('role') == 'farmer')
  officers = sum(1 for u in unique_users if u.get('role') == 'officer')
  admins = sum(1 for u in unique_users if u.get('role') == 'admin')

  return jsonify({
    'status': 'success',
    'stats': {
      'total_users': total_users,
      'farmers': farmers,
      'officers': officers,
      'admins': admins,
      'total_requests': total_requests,
      'pending_requests': pending,
      'approved_requests': approved,
      'rejected_requests': rejected,
    }
  }), 200


@app.route('/admin/audit-log', methods=['GET'])
def admin_audit_log():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  return jsonify({'status': 'success', 'log': audit_log}), 200


# ---------------------------------------------------------------------------
# ML Model & Realtime Water Release Prediction Endpoints
# ---------------------------------------------------------------------------
ML_MODEL_FILE = os.path.join(os.path.dirname(__file__), 'water_release_model.pkl')
ML_FEATURES_FILE = os.path.join(os.path.dirname(__file__), 'model_features.json')

water_release_model = None
water_model_metadata = {}

if os.path.exists(ML_MODEL_FILE):
  try:
    water_release_model = joblib.load(ML_MODEL_FILE)
    print("Successfully loaded ML water release model.")
  except Exception as e:
    print("Error loading ML model:", e)

if os.path.exists(ML_FEATURES_FILE):
  try:
    with open(ML_FEATURES_FILE, 'r', encoding='utf-8') as fh:
      water_model_metadata = json.load(fh)
  except Exception as e:
    print("Error loading model metadata:", e)

try:
  import realtime_fetcher
except ImportError:
  realtime_fetcher = None


@app.route('/api/model-info', methods=['GET'])
def get_model_info():
  """Returns model metrics, feature importances, and required inputs."""
  return jsonify({
    'status': 'success',
    'model_loaded': water_release_model is not None,
    'metadata': water_model_metadata
  }), 200


@app.route('/api/realtime-reservoir-data', methods=['GET'])
def get_realtime_reservoir_data():
  """Fetches real-time water level, capacity, date & rainfall from ArcGIS & Weather API."""
  reservoir = request.args.get('reservoir', 'Mahakandarawa')
  if not realtime_fetcher:
    return jsonify({'status': 'error', 'message': 'realtime_fetcher module not available'}), 500

  payload, meta = realtime_fetcher.get_realtime_feature_payload(reservoir)
  return jsonify({
    'status': 'success',
    'metadata': meta,
    'features': payload
  }), 200


@app.route('/api/predict-release', methods=['POST'])
def predict_water_release():
  """
  Predicts water release amount.
  Accepts JSON body with features, OR uses live fetched data if body/fields are omitted.
  """
  if water_release_model is None:
    return jsonify({'status': 'error', 'message': 'ML model is not loaded. Run train_model.py first.'}), 500

  try:
    data = request.get_json(silent=True) or {}
    reservoir = data.get('reservoir', 'Mahakandarawa')


    # Get live baseline payload, then override with any custom inputs
    if realtime_fetcher:
      features_dict, meta = realtime_fetcher.get_realtime_feature_payload(reservoir, custom_overrides=data)
    else:
      features_dict = {
        'Reservoir Water Level': float(data.get('water_level', 15.0)),
        'Reservoir Capacity': float(data.get('capacity', 45157.0)),
        'Rainfall (Nachchaduwa)': float(data.get('rainfall', 0.0)),
        'prev_day_level': float(data.get('prev_day_level', 15.0)),
        'prev_day_release': float(data.get('prev_day_release', 30.0)),
        'rainfall_3day_sum': float(data.get('rainfall_3day_sum', 0.0)),
        'rainfall_7day_sum': float(data.get('rainfall_7day_sum', 0.0)),
        'level_change': float(data.get('level_change', 0.0))
      }
      meta = {'reservoir_name': reservoir, 'date': 'manual_input'}

    feature_cols = water_model_metadata.get('feature_columns', [
      'Reservoir Water Level', 'Reservoir Capacity', 'Rainfall (Nachchaduwa)',
      'prev_day_level', 'prev_day_release', 'rainfall_3day_sum',
      'rainfall_7day_sum', 'level_change'
    ])

    df_input = pd.DataFrame([features_dict])[feature_cols]
    prediction = water_release_model.predict(df_input)[0]
    prediction_val = max(0.0, float(round(prediction, 4)))

    # Tercile thresholds based on 33.3% quantiles of historical dataset (Low < 80, Medium 80-150, High > 150)
    if prediction_val < 80.0:
      release_status = 'Low'
    elif prediction_val <= 150.0:
      release_status = 'Medium'
    else:
      release_status = 'High'

    return jsonify({
      'status': 'success',
      'predicted_water_release': prediction_val,
      'release_status': release_status,
      'unit': 'Acft/Day',
      'reservoir': meta.get('reservoir_name', reservoir),
      'date': meta.get('date', 'N/A'),
      'input_features': features_dict,
      'metadata': meta
    }), 200

  except Exception as e:
    return jsonify({'status': 'error', 'message': str(e)}), 400


if __name__ == '__main__':
  initialize_persistent_users()
  app.run(host=os.environ.get('API_HOST', '127.0.0.1'),
          port=int(os.environ.get('PORT', os.environ.get('API_PORT', '5000'))),
          debug=False)

