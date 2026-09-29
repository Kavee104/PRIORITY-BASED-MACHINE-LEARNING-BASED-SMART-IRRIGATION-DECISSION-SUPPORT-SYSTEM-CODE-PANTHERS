# Smart Irrigation

Flutter client with a Flask API for farmer fields, water requests, sensor
readings, priority schedules, and water release predictions.

## Run locally on Windows

Install Python 3.12 and the Flutter SDK. For this workspace, the Flutter SDK is
in `..\.tools\flutter`. Run these commands from this project directory in
PowerShell.

First-time backend setup:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe train_model.py
```

Start the API in one terminal:

```powershell
.\.venv\Scripts\python.exe -m flask --app app run --host 127.0.0.1 --port 5000
```

Check `http://127.0.0.1:5000/api/model-info` in a browser. It should report
`"model_loaded": true` after training.

Start the Flutter web client in another terminal:

```powershell
& '..\.tools\flutter\bin\flutter.bat' --no-version-check pub get
& '..\.tools\flutter\bin\flutter.bat' --no-version-check run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

Open `http://127.0.0.1:8080`. The app uses `http://localhost:5000` as its
default API base on web. If the API runs elsewhere, pass
`--dart-define=API_BASE_URL=http://host:port` to `flutter run`.

The Android emulator uses `http://10.0.2.2:5000` by default. For a physical
device, point `API_BASE_URL` at the computer's reachable LAN address.

MySQL and Arduino are optional for the original local features. The API falls
back to JSON files for some users, fields, and requests. The ESP32 integration
requires MySQL. External weather and reservoir data require internet access.

## ESP32 prototype setup

The prototype sends an ESP32 reading by Wi-Fi to Flask, stores it in MySQL,
and shows it in the existing farmer and admin dashboards by REST polling.
The former USB Arduino `GET /sensor-data` endpoint is still available for
legacy consumers. The ESP32 uses authenticated `POST /sensor-data`.

Set these environment variables in the PowerShell terminal that starts Flask
and the setup commands. Use your own MySQL credentials; the default password
is empty. Use a long random session secret that remains the same when Flask
restarts, since changing it invalidates existing farmer sessions. The example
below uses placeholders.

```powershell
$env:MYSQL_HOST = '127.0.0.1'
$env:MYSQL_PORT = '3306'
$env:MYSQL_DATABASE = 'smart_irrigation_db'
$env:MYSQL_USER = 'YOUR_MYSQL_USER'
$env:MYSQL_PASSWORD = 'YOUR_MYSQL_PASSWORD'
$env:SESSION_SECRET = 'REPLACE_WITH_A_LONG_RANDOM_SECRET'
$env:IOT_OFFLINE_SECONDS = '30'
```

Create the database first if it does not exist, and make sure the account has
permission to create tables. Apply the additive migration with:

```powershell
.\.venv\Scripts\python.exe iot_manage.py migrate
```

This applies `iot_schema.sql`, which creates `iot_devices`, `sensor_readings`,
and `request_sensor_snapshots` without changing existing tables. Running it
again is safe. Select a farmer already in `users.json` and a ZoneNo assigned
to one of that farmer's fields in MySQL `field_profile` or `fields.json`.
Find these values in the user dashboard or the data files. Register the ESP32:

```powershell
.\.venv\Scripts\python.exe iot_manage.py register --device-id ESP32_ZONE_01 --device-name 'Zone 01 sensor' --farmer-id 47270 --zone-no 5
```

The command prompts for a device token of at least 16 characters. Use a
unique random token and copy it into the sketch. MySQL stores only its SHA-256
hash. The IDs above are examples; confirm the farmer and zone exist locally.
The equivalent manual SQL is shown as a commented example in `iot_schema.sql`.

Find the PC's LAN IPv4 address with `ipconfig`. The PC and ESP32 must be
reachable on the same network, and the firewall must allow inbound TCP 5000.
Start Flask for LAN access in its own terminal with the same environment:

```powershell
$env:API_HOST = '0.0.0.0'
$env:API_PORT = '5000'
.\.venv\Scripts\python.exe app.py
```

Alternatively use `python -m flask --app app run --host 0.0.0.0 --port 5000`.
Do not expose this development server to the public internet. The existing
admin key and demo authentication are intended only for this local prototype.

In `esp32_sensor_client/esp32_sensor_client.ino`, replace `wifiSsid`,
`wifiPassword`, `serverUrl`, `deviceId`, and `deviceToken`. Set `serverUrl` to
`http://<PC-LAN-IP>:5000/sensor-data`; `localhost` or `127.0.0.1` would point
at the ESP32 itself. Upload to an ESP32 using Arduino IDE with ESP32 board
support, then open Serial Monitor at 115200 baud. `useDummyData = true` sends
changing values every ten seconds. Keep it true until the real soil and
temperature sensor models, pins, libraries, and calibration are known.

Start Flutter web from another terminal. For a browser on the same PC,
`http://localhost:5000` is the default API URL. For a browser on another
device, pass the PC's LAN IP:

```powershell
& '..\.tools\flutter\bin\flutter.bat' --no-version-check run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=API_BASE_URL=http://<PC-LAN-IP>:5000
```

If port 8080 is occupied, choose another `--web-port`, such as 8081. Open
`http://<PC-LAN-IP>:8080` from the other device. A physical Android build also
needs the LAN API URL supplied with `--dart-define`; the emulator default is
`http://10.0.2.2:5000`.

### End-to-end check

1. Confirm `iot_manage.py migrate` and `register` succeeded.
2. Start Flask, then the ESP32. In Serial Monitor, confirm repeated HTTP 201
   responses. HTTP 401 means a wrong token, HTTP 404 means an unknown or
   disabled device, and HTTP 503 means MySQL is unavailable.
3. Log in as the mapped farmer through the backend. The Zone dashboard should
   show its own moisture, temperature, and `ESP32 Online`. Other farmers should
   not see this device. A local-only demo login cannot retrieve owner-scoped
   readings because it has no backend session token.
4. Stop or disconnect the ESP32. After `IOT_OFFLINE_SECONDS`, the dashboard
   should show `ESP32 Offline`, with the last reading retained.
5. Reconnect the ESP32 and submit a water request for a field in its zone.
   The admin request row should show the device ID and values captured at
   request time. New readings must not change that snapshot. If no current
   device reading exists when a request is made, the request still succeeds
   and shows `No snapshot`.
6. Log in as admin. The Zone ESP32 Sensors section should show all registered
   devices. Approve or reject the request using the existing controls.
7. Optional: check `GET /api/sensor-history/ESP32_ZONE_01?limit=100` with the
   existing `X-Admin-Key` header or a mapped farmer bearer session. The farmer
   endpoint is `GET /api/user/sensor-data`; the admin endpoint is
   `GET /api/admin/sensors`.

The physical sensor mode is a placeholder. `readSoilMoisture()` and
`readTemperature()` must be implemented for the actual hardware; no sensor
library or pin mapping has been assumed.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Backend configuration

Configure credentials with environment variables before starting `app.py`:

- `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`
- `ADMIN_KEY`, `ADMIN_PASSWORD`, `OPENWEATHER_API_KEY`

The local `users.json` account store is generated at runtime and is excluded
from Git to prevent account data and password hashes from being published.
