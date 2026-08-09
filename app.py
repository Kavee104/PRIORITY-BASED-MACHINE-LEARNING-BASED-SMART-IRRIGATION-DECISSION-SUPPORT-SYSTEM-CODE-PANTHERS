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


# ---------------------------------------------------------------------------
# In-memory water requests store
# ---------------------------------------------------------------------------
water_requests = []  # list of dicts
_next_request_id = 1

# In-memory farmer fields store (keyed by farmer_id)
farmer_fields = {}

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


# Seed default farmer fields for demo
farmer_fields[101] = [
  {"FieldID": 101, "ZoneNo": 1, "Size": 4.5, "CropType": "Paddy Rice", "Moisture": "68%", "Status": "Optimal"},
  {"FieldID": 102, "ZoneNo": 2, "Size": 2.8, "CropType": "Maize", "Moisture": "42%", "Status": "Needs Water"},
  {"FieldID": 103, "ZoneNo": 3, "Size": 3.2, "CropType": "Vegetables", "Moisture": "75%", "Status": "Optimal"},
]

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
  _audit('USER_CREATED', 'admin', f'Created user "{username}" with role "{role}"')
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
  _audit('USER_LOGIN', username, f'Logged in via /auth/login (role: {user["role"]})')
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

    _audit('USER_LOGIN', email, f'Logged in via /login (role: {user.get("role")})')
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


# ---------------------------------------------------------------------------
# Farmer Fields endpoints
# ---------------------------------------------------------------------------
@app.route('/fields/<int:farmer_id>', methods=['GET'])
def get_farmer_fields(farmer_id):
  fields = farmer_fields.get(farmer_id, [])
  return jsonify({'fields': fields}), 200


@app.route('/fields/<int:farmer_id>', methods=['POST'])
def add_farmer_field(farmer_id):
  data = request.get_json(force=True)
  zone_no = data.get('zone_no', 1)
  size = data.get('size', 1.0)
  crop_type = data.get('crop_type', 'General')

  if farmer_id not in farmer_fields:
    farmer_fields[farmer_id] = []

  new_id = max([f['FieldID'] for f in farmer_fields[farmer_id]], default=100) + 1
  new_field = {
    'FieldID': new_id,
    'ZoneNo': zone_no,
    'Size': size,
    'CropType': crop_type,
    'Moisture': f'{random.randint(30, 80)}%',
    'Status': 'Optimal' if random.random() > 0.3 else 'Needs Water',
  }
  farmer_fields[farmer_id].append(new_field)
  _audit('FIELD_CREATED', f'farmer_{farmer_id}', f'Registered field #{new_id} in Zone {zone_no}')
  return jsonify({'status': 'success', 'field': new_field}), 201


# ---------------------------------------------------------------------------
# Water Request endpoints
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

  # Look up zone name from farmer_fields
  zone_name = f'Zone (Field #{field_id})'
  fields = farmer_fields.get(farmer_id, [])
  for f in fields:
    if f.get('FieldID') == field_id:
      zone_name = f'Zone {f.get("ZoneNo", "?")} ({f.get("CropType", "General")})'
      break

  req = {
    'RequestID': _next_request_id,
    'farmer_id': farmer_id,
    'FieldID': field_id,
    'ZoneName': zone_name,
    'Status': 'Pending',
    'RequestTime': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'farmer_name': f'Farmer #{farmer_id}',
  }
  _next_request_id += 1
  water_requests.insert(0, req)  # newest first
  _audit('WATER_REQUEST', f'farmer_{farmer_id}', f'Submitted water request #{req["RequestID"]} for field #{field_id} ({zone_name})')
  return jsonify({'status': 'success', 'request': req}), 201


@app.route('/my-requests/<int:farmer_id>', methods=['GET'])
def get_my_requests(farmer_id):
  import datetime
  my_reqs = [r for r in water_requests if r.get('farmer_id') == farmer_id]
  # Convert timestamps to relative time for display
  now = datetime.datetime.now()
  display_reqs = []
  for r in my_reqs:
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
  return jsonify({'status': 'success', 'requests': water_requests}), 200


@app.route('/admin/water-requests/<int:req_id>/approve', methods=['POST'])
def admin_approve_request(req_id):
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  for r in water_requests:
    if r['RequestID'] == req_id:
      r['Status'] = 'Approved'
      _audit('REQUEST_APPROVED', 'admin', f'Approved water request #{req_id} for {r["ZoneName"]}')
      return jsonify({'status': 'success', 'request': r}), 200
  return jsonify({'status': 'error', 'message': 'Request not found'}), 404


@app.route('/admin/water-requests/<int:req_id>/reject', methods=['POST'])
def admin_reject_request(req_id):
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401
  for r in water_requests:
    if r['RequestID'] == req_id:
      r['Status'] = 'Rejected'
      _audit('REQUEST_REJECTED', 'admin', f'Rejected water request #{req_id} for {r["ZoneName"]}')
      return jsonify({'status': 'success', 'request': r}), 200
  return jsonify({'status': 'error', 'message': 'Request not found'}), 404


# ---------------------------------------------------------------------------
# Admin Stats & Audit Trail
# ---------------------------------------------------------------------------
@app.route('/admin/stats', methods=['GET'])
def admin_stats():
  if not _admin_key_valid(request):
    return jsonify({'status': 'error', 'message': 'admin key required'}), 401

  total_users = len(users)
  total_requests = len(water_requests)
  pending = sum(1 for r in water_requests if r['Status'] == 'Pending')
  approved = sum(1 for r in water_requests if r['Status'] == 'Approved')
  rejected = sum(1 for r in water_requests if r['Status'] == 'Rejected')
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


if __name__ == '__main__':
  # Run development server on port 5000
  app.run(host='0.0.0.0', port=5000, debug=True)
