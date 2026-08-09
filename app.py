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
        if changed:
          _write_users_file(loaded)
        admin = loaded.get(DEFAULT_ADMIN_USERNAME)
        if (
            admin is None
            or admin.get('role') != 'admin'
            or not check_password_hash(admin.get('password_hash', ''), default_admin_password)
        ):
          loaded[DEFAULT_ADMIN_USERNAME] = {
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
  if not record or record['otp'] != otp or not record.get('verified'):
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
  _write_users_file(users)
  return jsonify({'status': 'success', 'username': username, 'role': role}), 200


@app.route('/admin/users', methods=['GET'])
def admin_list_users():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  safe = [{ 'username': u, 'role': users[u]['role'] } for u in users]
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
  return jsonify({'status': 'success', 'username': username, 'role': user['role']}), 200


@app.route('/login', methods=['POST'])
def app_login():
  data = request.get_json(force=True)
  email = data.get('email', '').strip()
  password = data.get('password', '').strip()

  user = users.get(email.lower())
  if user and check_password_hash(user.get('password_hash', ''), password):
    if user.get('role') == 'admin':
      return jsonify({
        'status': 'success',
        'name': 'Admin',
        'role': 'admin'
      }), 200

    return jsonify({
      'status': 'success',
      'name': email,
      'role': user.get('role')
    }), 200

  return jsonify({'error': 'User not found'}), 404


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


if __name__ == '__main__':
  # Run development server on port 5000
  app.run(host='0.0.0.0', port=5000, debug=True)
