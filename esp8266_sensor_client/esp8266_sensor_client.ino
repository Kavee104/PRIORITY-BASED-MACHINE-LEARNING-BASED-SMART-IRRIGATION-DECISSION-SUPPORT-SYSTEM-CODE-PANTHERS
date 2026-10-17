#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecureBearSSL.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <math.h>

#include "device_secrets.h"

// NodeMCU ESP8266 wiring:
//   Capacitive soil sensor AO -> A0
//   DS18B20 DATA              -> D2 / GPIO4
//   DS18B20 DATA to 3.3V through a 4.7 kOhm pull-up resistor

constexpr uint8_t SOIL_PIN = A0;
constexpr uint8_t TEMP_PIN = D2;

const char* wifiSsid = WIFI_SSID;
const char* wifiPassword = WIFI_PASSWORD;
const char* serverUrl =
    "https://bsmhjdwtbpbhlktjmocj.supabase.co/functions/v1/ingest-sensor";

// Keep this ID unchanged: Supabase maps it to farmer_id 6, zone_no 1.
const char* deviceId = "ESP32_ZONE_01";
const char* deviceToken = DEVICE_ESP32_ZONE_01_SECRET;

// Temporary calibration values. Replace after measuring the sensor in dry air
// and fully wet soil. Higher raw values are treated as drier.
constexpr int SOIL_DRY_RAW = 850;
constexpr int SOIL_WET_RAW = 350;
constexpr unsigned long SEND_INTERVAL_MS = 10000;
constexpr unsigned long WIFI_TIMEOUT_MS = 20000;

OneWire oneWire(TEMP_PIN);
DallasTemperature temperatureSensor(&oneWire);
unsigned long lastSendMs = 0;

void diagnoseConfiguredWifi() {
  Serial.println("Scanning for the configured 2.4 GHz SSID...");
  const int networkCount = WiFi.scanNetworks();
  bool found = false;

  for (int index = 0; index < networkCount; ++index) {
    if (WiFi.SSID(index) == wifiSsid) {
      found = true;
      Serial.print("Configured SSID is visible on channel ");
      Serial.print(WiFi.channel(index));
      Serial.print(" with RSSI ");
      Serial.print(WiFi.RSSI(index));
      Serial.println(" dBm. Check the password/security mode.");
      break;
    }
  }

  if (!found) {
    Serial.println(
        "Configured SSID is not visible. Enable its 2.4 GHz hotspot/band.");
  }
  WiFi.scanDelete();
}

float readSoilMoisture() {
  long total = 0;
  constexpr int sampleCount = 10;

  for (int index = 0; index < sampleCount; ++index) {
    total += analogRead(SOIL_PIN);
    delay(20);
  }

  const int rawValue = total / sampleCount;

  Serial.print("Soil RAW value: ");
  Serial.println(rawValue);
  if (rawValue >= 1018) {
    Serial.println(
        "ERROR: Soil input saturated. Use 3.3V, AO->A0 and common GND.");
    return NAN;
  }

  float moisturePercent = 100.0f * (SOIL_DRY_RAW - rawValue) /
                          (SOIL_DRY_RAW - SOIL_WET_RAW);
  moisturePercent = constrain(moisturePercent, 0.0f, 100.0f);

  Serial.print("Soil moisture: ");
  Serial.print(moisturePercent, 1);
  Serial.println("%");
  return moisturePercent;
}

float readTemperature() {
  temperatureSensor.requestTemperatures();
  const float temperature = temperatureSensor.getTempCByIndex(0);

  if (temperature == DEVICE_DISCONNECTED_C || temperature < -50.0f ||
      temperature > 100.0f) {
    Serial.println("ERROR: DS18B20 temperature probe not detected.");
    return NAN;
  }

  Serial.print("Temperature: ");
  Serial.print(temperature, 2);
  Serial.println(" C");
  return temperature;
}

bool connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return true;

  Serial.println();
  Serial.print("Connecting to Wi-Fi SSID: ");
  Serial.println(wifiSsid);

  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(500);
  WiFi.begin(wifiSsid, wifiPassword);

  const unsigned long startedAt = millis();
  while (WiFi.status() != WL_CONNECTED &&
         millis() - startedAt < WIFI_TIMEOUT_MS) {
    Serial.print('.');
    delay(500);
  }
  Serial.println();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Wi-Fi connection failed; upload skipped.");
    diagnoseConfiguredWifi();
    return false;
  }

  Serial.print("Wi-Fi connected. ESP8266 IP: ");
  Serial.println(WiFi.localIP());
  Serial.print("Signal strength: ");
  Serial.print(WiFi.RSSI());
  Serial.println(" dBm");
  return true;
}

void sendSensorData(float moisture, float temperature) {
  if (WiFi.status() != WL_CONNECTED) return;

  const String payload =
      String("{\"deviceId\":\"") + deviceId +
      "\",\"deviceToken\":\"" + deviceToken +
      "\",\"moisture\":" + String(moisture, 1) +
      ",\"temperature\":" + String(temperature, 1) + "}";

  BearSSL::WiFiClientSecure client;
  // Prototype setting. Pin the Supabase certificate/CA before production use.
  client.setInsecure();
  client.setTimeout(30000);

  HTTPClient http;
  http.useHTTP10(true);
  http.setTimeout(30000);
  if (!http.begin(client, serverUrl)) {
    Serial.println("ERROR: HTTPS initialization failed.");
    return;
  }

  http.addHeader("Content-Type", "application/json");
  const int statusCode = http.POST(payload);
  Serial.print("HTTP status: ");
  Serial.println(statusCode);

  if (statusCode > 0) {
    Serial.print("Server response: ");
    Serial.println(http.getString());
  } else {
    Serial.print("HTTPS error: ");
    Serial.println(HTTPClient::errorToString(statusCode).c_str());
  }

  if (statusCode == 201) {
    Serial.println("SUCCESS: Sensor data stored in Supabase.");
  } else if (statusCode == 401 || statusCode == 403) {
    Serial.println("ERROR: Device authentication failed; rotate/check token.");
  }

  http.end();
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println();
  Serial.println("Smart Irrigation - ESP8266 NodeMCU");

  pinMode(SOIL_PIN, INPUT);
  temperatureSensor.begin();
  Serial.print("Temperature probes detected: ");
  Serial.println(temperatureSensor.getDeviceCount());

  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  connectWifi();
  lastSendMs = millis() - SEND_INTERVAL_MS;
}

void loop() {
  if (millis() - lastSendMs < SEND_INTERVAL_MS) {
    delay(50);
    return;
  }
  lastSendMs = millis();

  if (!connectWifi()) return;

  Serial.println();
  Serial.println("Reading physical sensors...");
  const float moisture = readSoilMoisture();
  const float temperature = readTemperature();

  if (!isfinite(moisture) || !isfinite(temperature)) {
    Serial.println("ERROR: Invalid reading; cloud upload skipped.");
    return;
  }

  sendSensorData(moisture, temperature);
}
