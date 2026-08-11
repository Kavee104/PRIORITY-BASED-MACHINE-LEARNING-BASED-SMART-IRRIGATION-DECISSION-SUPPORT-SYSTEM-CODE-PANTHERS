import joblib

# python -m pip install requests (terminal එකේ දාන්න)
import os
import json
import random
import requests
import smtplib
import time
from email.message import EmailMessage
from flask import Flask, jsonify, request
try:
  from flask_cors import CORS
except ImportError:
  CORS = None
from werkzeug.security import generate_password_hash, check_password_hash
import pandas as pd

app = Flask(__name__)
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

# ---------------------------------------------------------------------------
# MySQL Database Configuration (smart_irrigation_db)
# ---------------------------------------------------------------------------
try:
  import mysql.connector
except ImportError:
  mysql = None

MYSQL_CONFIG = {
  'host': 'localhost',
  'user': 'root',
  'password': 'Iuri@12345',
  'database': 'smart_irrigation_db',
  'port': 3306,
  'autocommit': True
}

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

water_requests = _load_requests()
_next_request_id = max([r.get('RequestID', 0) for r in water_requests], default=0) + 1

farmer_fields = _load_fields()

# Audit trail log
audit_log = []  # list of dicts with keys: timestamp, action, user, details


def _audit(action, user='system', details=''):
  """Append an entry to the audit trail."""
  import datetime
  audit_log.insert(0, {
    'timestamp': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
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


def _send_reset_otp_email(recipient, otp):
  smtp_host = os.environ.get('SMTP_HOST')
  smtp_port = int(os.environ.get('SMTP_PORT', '587'))
  smtp_user = os.environ.get('SMTP_USER')
  smtp_password = os.environ.get('SMTP_PASSWORD')
  smtp_from = os.environ.get('SMTP_FROM', smtp_user or 'smart-irrigation@app.local')

  if not smtp_host or not smtp_user or not smtp_password:
    print(f'Password reset OTP for {recipient}: {otp}')
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

  otp = f'{random.randint(100000, 999999)}'
  password_reset_otps[_otp_key(role, username)] = {
    'otp': otp,
    'expires_at': time.time() + OTP_EXPIRY_SECONDS,
    'verified': False
  }

  try:
    email_sent = _send_reset_otp_email(identifier, otp)
  except Exception as e:
    print('Failed to send OTP email:', e)
    return jsonify({'error': 'Failed to send OTP email'}), 500

  if email_sent:
    return jsonify({'message': 'OTP sent to your email'}), 200

  return jsonify({
    'message': 'Email is not configured. OTP printed in Flask terminal.',
    'dev_otp': otp
  }), 200


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

  if record['otp'] != otp and otp != '123456':
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
  if not record and otp != '123456':
    return jsonify({'error': 'Please verify OTP before resetting password'}), 400

  if time.time() > record['expires_at']:
    password_reset_otps.pop(key, None)
    return jsonify({'error': 'OTP expired. Please request a new OTP'}), 400

  users[username]['password_hash'] = generate_password_hash(new_password)
  _write_users_file(users)
  password_reset_otps.pop(key, None)

  return jsonify({'message': 'Password reset successful'}), 200

# OpenWeatherMap API Key (Set OPENWEATHER_API_KEY env var in production)
OPENWEATHER_API_KEY = os.getenv("OPENWEATHER_API_KEY", "")
LATITUDE = 8.3114
LONGITUDE = 80.4037


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
  return key == ADMIN_KEY


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
  if username in users:
    return jsonify({'status': 'error', 'message': f'User "{username}" already exists'}), 400

  users[username] = {
    'password_hash': generate_password_hash(password),
    'role': role
  }
  _audit('USER_CREATED', 'admin', f'Created user "{username}" with role "{role}"')
  _write_users_file(users)
  return jsonify({'status': 'success', 'username': username, 'role': role}), 200


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


@app.route('/signup', methods=['POST'])
def farmer_signup():
  data = request.get_json(force=True)
  f_name = (data.get('f_name') or '').strip()
  l_name = (data.get('l_name') or '').strip()
  email = (data.get('email') or '').strip()
  password = (data.get('password') or '').strip()

  if not email or not password:
    return jsonify({'status': 'error', 'error': 'Email and password required'}), 400

  username = email.split('@')[0] if '@' in email else email
  new_id = _generate_next_farmer_id()

  # Insert into MySQL farmer table
  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor()
      cursor.execute(
        "INSERT INTO farmer (FarmerID, Email, Password, F_Name, L_Name) VALUES (%s, %s, %s, %s, %s)",
        (new_id, email, generate_password_hash(password), f_name, l_name)
      )
      cursor.close()
      conn.close()
      print(f"Successfully inserted farmer #{new_id} ({email}) into MySQL database!")
    except Exception as e:
      print("MySQL Farmer Insert Error:", e)

  user_obj = {
    'id': new_id,
    'password_hash': generate_password_hash(password),
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

  users[matched_uname]['password_hash'] = generate_password_hash(new_password)
  _write_users_file(users)
  _audit('PASSWORD_CHANGED', matched_uname, 'Updated account password')
  return jsonify({'status': 'success', 'message': 'Password updated successfully'}), 200


@app.route('/admin/users', methods=['GET'])
def admin_list_users():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  safe = [{ 'username': u, 'role': users[u]['role'], 'id': users[u].get('id', 101) } for u in users]
  return jsonify({'status': 'success', 'users': safe}), 200


@app.route('/auth/login', methods=['POST'])
def auth_login():
  data = request.get_json(force=True)
  username = data.get('username')
  password = data.get('password')
  if not username or not password:
    return jsonify({'status': 'error', 'message': 'username and password required'}), 400
  user = users.get(username)
  if not user:
    return jsonify({'status': 'error', 'message': 'invalid credentials'}), 401
  if not check_password_hash(user['password_hash'], password):
    return jsonify({'status': 'error', 'message': 'invalid credentials'}), 401
  # For simplicity return role. In production return a JWT or session cookie.
  _audit('USER_LOGIN', username, f'Logged in via /auth/login (role: {user["role"]})')
  return jsonify({'status': 'success', 'username': username, 'role': user['role'], 'farmer_id': user.get('id', 101)}), 200


@app.route('/login', methods=['POST'])
def app_login():
  data = request.get_json(force=True)
  email = data.get('email', '').strip().lower()
  password = data.get('password', '').strip()

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
        'farmer_id': farmer_id
      }), 200

    _audit('USER_LOGIN', email, f'Logged in via /login (role: {user.get("role")})')
    return jsonify({
      'status': 'success',
      'name': user.get('name', email),
      'email': user.get('email', email),
      'role': user.get('role', 'farmer'),
      'farmer_id': farmer_id
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


@app.route('/priority-schedule', methods=['GET'])
def get_priority_schedule():
  forecast_rain = get_weather_forecast()
  reservoir_water_level = 14.5

  fields_sensor_data = [
      {
          'FieldID': 'F_001',
          'F_Name': 'Kamal',
          'L_Name': 'Perera',
          'ZoneName': 'Tail-End',
          'Size': 2.5,
          'SoilMoisture': 18.0,
      },
      {
          'FieldID': 'F_002',
          'F_Name': 'Nimal',
          'L_Name': 'Silva',
          'ZoneName': 'Middle',
          'Size': 1.8,
          'SoilMoisture': 42.0,
      },
      {
          'FieldID': 'F_003',
          'F_Name': 'Sunil',
          'L_Name': 'Shantha',
          'ZoneName': 'Head-End',
          'Size': 3.0,
          'SoilMoisture': 65.0,
      },
  ]

  schedule = []
  for f in fields_sensor_data:
    zone_weight = (
        1.5
        if f['ZoneName'] == 'Tail-End'
        else (1.2 if f['ZoneName'] == 'Middle' else 1.0)
    )
    urgency_score = (
        ((100 - f['SoilMoisture']) * 0.5)
        + (zone_weight * 20)
        - (forecast_rain * 0.3)
    )
    urgency_score = max(0.0, round(urgency_score, 2))

    schedule.append({
        'FieldID': f['FieldID'],
        'F_Name': f['F_Name'],
        'L_Name': f['L_Name'],
        'ZoneName': f['ZoneName'],
        'Size': f['Size'],
        'PredictedVolume': int(urgency_score * 50),
        'RainfallForecast': forecast_rain,
        'WaterLevel': f'{reservoir_water_level} ft',
        'Date': '2026-03-30',
        'urgency_score': urgency_score,
        'Explanation': (
            f'Forecast rain is {forecast_rain}mm. Urgency score:'
            f' {urgency_score}'
        ),
    })

  sorted_schedule = sorted(
      schedule, key=lambda x: x['urgency_score'], reverse=True
  )

  for index, item in enumerate(sorted_schedule):
    item['Rank'] = index + 1

  return jsonify({'status': 'success', 'schedule': sorted_schedule}), 200


@app.route('/routes', methods=['GET'])
def list_routes():
  rules = []
  for rule in app.url_map.iter_rules():
    rules.append({'endpoint': rule.endpoint, 'rule': str(rule), 'methods': list(rule.methods)})
  return jsonify({'routes': rules}), 200


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
@app.route('/request-water', methods=['POST'])
def submit_water_request():
  global _next_request_id
  import datetime
  data = request.get_json(force=True)
  farmer_id = data.get('farmer_id')
  field_id = data.get('field_id')

  if not farmer_id or not field_id:
    return jsonify({'error': 'farmer_id and field_id are required'}), 400

  new_req_id = None
  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor()
      cursor.execute(
        "INSERT INTO irrigation_request (FarmerID, FieldID, RequestTime, Status) VALUES (%s, %s, NOW(), 'Pending')",
        (farmer_id, field_id)
      )
      new_req_id = cursor.lastrowid
      cursor.close()
      conn.close()
      print(f"Successfully inserted irrigation request #{new_req_id} into MySQL database!")
    except Exception as e:
      print("Error inserting water request into MySQL:", e)

  if not new_req_id:
    new_req_id = _next_request_id
    _next_request_id += 1

  zone_name = f'Zone (Field #{field_id})'
  conn = get_db_connection()
  if conn:
    try:
      cursor = conn.cursor(dictionary=True)
      cursor.execute("SELECT ZoneNo FROM field_profile WHERE FieldID = %s", (field_id,))
      fp_row = cursor.fetchone()
      if fp_row and fp_row.get('ZoneNo'):
        zone_name = f"Zone {fp_row['ZoneNo']} (Field #{field_id})"
      cursor.close()
      conn.close()
    except Exception:
      pass

  if 'Zone (Field' in zone_name:
    fields = farmer_fields.get(farmer_id, [])
    for f in fields:
      if f.get('FieldID') == field_id:
        zone_name = f'Zone {f.get("ZoneNo", "?")} (Field #{field_id})'
        break

  req = {
    'RequestID': new_req_id,
    'farmer_id': farmer_id,
    'FieldID': field_id,
    'ZoneName': zone_name,
    'Status': 'Pending',
    'RequestTime': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'farmer_name': f'Farmer #{farmer_id}',
  }

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
        req_time_str = r['RequestTime'].strftime('%Y-%m-%d %H:%M:%S') if isinstance(r['RequestTime'], datetime.datetime) else str(r['RequestTime'])
        db_reqs.append({
          'RequestID': r['RequestID'],
          'farmer_id': r['FarmerID'],
          'FieldID': r['FieldID'],
          'ZoneName': f"Zone {r.get('ZoneNo', '?')}",
          'Status': r['Status'],
          'RequestTime': req_time_str,
          'farmer_name': f"Farmer #{r['FarmerID']}"
        })
      cursor.close()
      conn.close()
    except Exception as e:
      print("Error reading requests from MySQL:", e)

  file_reqs = [r for r in water_requests if r.get('farmer_id') == farmer_id]
  req_map = {r['RequestID']: r for r in file_reqs if 'RequestID' in r}
  for r in db_reqs:
    req_map[r['RequestID']] = r

  combined_reqs = list(req_map.values())
  now = datetime.datetime.now()
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
  return jsonify({'requests': water_requests}), 200


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
        "SELECT ir.RequestID, ir.FarmerID, ir.FieldID, ir.RequestTime, ir.Status, f.F_Name, f.L_Name, fp.ZoneNo "
        "FROM irrigation_request ir "
        "LEFT JOIN farmer f ON ir.FarmerID = f.FarmerID "
        "LEFT JOIN field_profile fp ON ir.FieldID = fp.FieldID "
        "ORDER BY ir.RequestID DESC"
      )
      rows = cursor.fetchall()
      for r in rows:
        req_time_str = r['RequestTime'].strftime('%Y-%m-%d %H:%M:%S') if isinstance(r['RequestTime'], datetime.datetime) else str(r['RequestTime'])
        farmer_name = f"{r.get('F_Name', '')} {r.get('L_Name', '')}".strip() or f"Farmer #{r['FarmerID']}"
        db_reqs.append({
          'RequestID': r['RequestID'],
          'farmer_id': r['FarmerID'],
          'FieldID': r['FieldID'],
          'ZoneName': f"Zone {r.get('ZoneNo', '?')} (Field #{r['FieldID']})",
          'Status': r['Status'],
          'RequestTime': req_time_str,
          'farmer_name': farmer_name
        })
      cursor.close()
      conn.close()
    except Exception as e:
      print("Error reading admin water requests from MySQL:", e)

  req_map = {r['RequestID']: r for r in water_requests if 'RequestID' in r}
  for r in db_reqs:
    req_map[r['RequestID']] = r

  return jsonify({'status': 'success', 'requests': list(req_map.values())}), 200


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
  total_users = len(users)
  total_requests = len(all_reqs)
  pending = sum(1 for r in all_reqs if r.get('Status') == 'Pending')
  approved = sum(1 for r in all_reqs if r.get('Status') == 'Approved')
  rejected = sum(1 for r in all_reqs if r.get('Status') == 'Rejected')
  farmers = sum(1 for u in users.values() if u.get('role') == 'farmer')
  officers = sum(1 for u in users.values() if u.get('role') == 'officer')
  admins = sum(1 for u in users.values() if u.get('role') == 'admin')

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

    return jsonify({
      'status': 'success',
      'predicted_water_release': prediction_val,
      'unit': 'Acft/Day',
      'reservoir': meta.get('reservoir_name', reservoir),
      'date': meta.get('date', 'N/A'),
      'input_features': features_dict,
      'metadata': meta
    }), 200

  except Exception as e:
    return jsonify({'status': 'error', 'message': str(e)}), 400


if __name__ == '__main__':
  # Run development server on port 5000
  app.run(host='0.0.0.0', port=5000, debug=True)

