#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <math.h>

#include "device_secrets.h"

// =====================================================
// SMART IRRIGATION - ESP32-S3 IoT CLIENT
// Board: ESP32-S3 N16R8
// =====================================================


// =====================================================
// 1. CONNECTION CONFIGURATION
// =====================================================

// Defined locally in the gitignored device_secrets.h file.
const char* wifiSsid = WIFI_SSID;
const char* wifiPassword = WIFI_PASSWORD;

// Supabase Edge Function
const char* serverUrl =
    "https://bsmhjdwtbpbhlktjmocj.supabase.co/functions/v1/ingest-sensor";

// Registered ESP32 device
const char* deviceId =
    "ESP32_ZONE_01";

// Defined locally in the gitignored device_secrets.h file.
// Never use Supabase service-role or database credentials here.
const char* deviceToken =
    DEVICE_ESP32_ZONE_01_SECRET;


// =====================================================
// 2. PROTOTYPE CONFIGURATION
// =====================================================

// true  = generate dummy sensor values
// false = use physical sensors later
const bool useDummyData = true;

// Send reading every 10 seconds
const unsigned long sendIntervalMs = 10000;

// Wi-Fi connection timeout
const unsigned long wifiTimeoutMs = 20000;

unsigned long lastSendMs = 0;
unsigned long sampleNumber = 0;


// =====================================================
// 3. REAL SENSOR FUNCTIONS
// =====================================================

// We will replace these later when the
// actual sensor models are connected.

float readSoilMoisture() {
  return NAN;
}

float readTemperature() {
  return NAN;
}


// =====================================================
// 4. PRINT WIFI STATUS
// =====================================================

void printWifiStatus() {

  Serial.print("Wi-Fi status code: ");
  Serial.println(WiFi.status());

  /*
    Common values:

    WL_IDLE_STATUS       = 0
    WL_NO_SSID_AVAIL     = 1
    WL_SCAN_COMPLETED    = 2
    WL_CONNECTED         = 3
    WL_CONNECT_FAILED    = 4
    WL_CONNECTION_LOST   = 5
    WL_DISCONNECTED      = 6
  */
}


// =====================================================
// 5. WIFI CONNECTION
// =====================================================

bool connectWifi() {

  // Already connected
  if (WiFi.status() == WL_CONNECTED) {
    return true;
  }

  Serial.println();
  Serial.println("============================");
  Serial.println("Connecting to Wi-Fi");
  Serial.println("============================");

  Serial.print("SSID: ");
  Serial.println(wifiSsid);

  // Explicitly configure station mode
  WiFi.mode(WIFI_STA);

  delay(300);

  // Clear previous connection attempt
  // but DO NOT erase saved credentials.
  WiFi.disconnect(false, false);

  delay(500);

  Serial.println("Starting Wi-Fi connection...");

  WiFi.begin(
    wifiSsid,
    wifiPassword
  );

  unsigned long startTime = millis();

  while (
    WiFi.status() != WL_CONNECTED &&
    millis() - startTime < wifiTimeoutMs
  ) {

    Serial.print(".");

    delay(500);
  }

  Serial.println();


  // CONNECTION SUCCESSFUL
  if (WiFi.status() == WL_CONNECTED) {

    Serial.println();
    Serial.println("Wi-Fi connected successfully!");

    Serial.print("ESP32 IP address: ");
    Serial.println(WiFi.localIP());

    Serial.print("Gateway: ");
    Serial.println(WiFi.gatewayIP());

    Serial.print("Signal strength: ");
    Serial.print(WiFi.RSSI());
    Serial.println(" dBm");

    Serial.print("Supabase endpoint: ");
    Serial.println(serverUrl);

    Serial.println();

    return true;
  }


  // CONNECTION FAILED
  Serial.println();
  Serial.println("Wi-Fi connection FAILED.");

  printWifiStatus();

  Serial.println(
    "Will try again on the next cycle."
  );

  return false;
}


// =====================================================
// 6. SEND DATA TO SUPABASE
// =====================================================

void sendSensorData(
  float moisture,
  float temperature
) {

  if (WiFi.status() != WL_CONNECTED) {

    Serial.println(
      "Wi-Fi disconnected. Cannot send data."
    );

    return;
  }


  // Create JSON body
  String payload =
      "{\"deviceId\":\"" +
      String(deviceId) +

      "\",\"deviceToken\":\"" +
      String(deviceToken) +

      "\",\"moisture\":" +
      String(moisture, 1) +

      ",\"temperature\":" +
      String(temperature, 1) +

      "}";


  Serial.println();
  Serial.println("----------------------------");

  Serial.print("Device: ");
  Serial.println(deviceId);

  Serial.print("Soil Moisture: ");
  Serial.print(moisture, 1);
  Serial.println("%");

  Serial.print("Temperature: ");
  Serial.print(temperature, 1);
  Serial.println(" °C");

  Serial.println("Sending data to Supabase...");


  WiFiClientSecure client;

  // Prototype connectivity test only. Replace with CA certificate
  // validation before using this outside the initial test.
  client.setInsecure();

  HTTPClient http;

  http.setConnectTimeout(5000);
  http.setTimeout(5000);


  if (!http.begin(client, serverUrl)) {

    Serial.println(
      "ERROR: Could not initialize HTTP connection."
    );

    return;
  }


  http.addHeader(
    "Content-Type",
    "application/json"
  );


  int statusCode =
      http.POST(payload);


  Serial.print("HTTP status: ");
  Serial.println(statusCode);


  if (statusCode > 0) {

    String response =
        http.getString();

    Serial.print("Server response: ");
    Serial.println(response);


    if (statusCode == 201) {

      Serial.println();
      Serial.println(
        "SUCCESS: Cloud sensor data stored."
      );

    } else if (
      statusCode == 401 ||
      statusCode == 403
    ) {

      Serial.println();
      Serial.println(
        "ERROR: Device token rejected."
      );

    } else {

      Serial.println();
      Serial.println(
        "Server returned an unexpected response."
      );
    }

  } else {

    Serial.println();
    Serial.print("HTTP connection error: ");

    Serial.println(
      http.errorToString(statusCode)
    );
  }


  http.end();

  Serial.println("----------------------------");
}


// =====================================================
// 7. SETUP
// =====================================================

void setup() {

  Serial.begin(115200);

  delay(2500);

  Serial.println();
  Serial.println();
  Serial.println("=================================");
  Serial.println(" SMART IRRIGATION IoT SYSTEM");
  Serial.println(" ESP32-S3 N16R8");
  Serial.println("=================================");

  Serial.print("Device ID: ");
  Serial.println(deviceId);

  Serial.print("Backend: ");
  Serial.println(serverUrl);

  Serial.println();


  // Disable automatic reconnect for now.
  // We manually control reconnection.
  WiFi.setAutoReconnect(false);

  // Prevent credential writing to flash
  WiFi.persistent(false);

  WiFi.mode(WIFI_STA);

  delay(500);

  connectWifi();


  // Allows first reading shortly after startup
  lastSendMs =
      millis() - sendIntervalMs;
}


// =====================================================
// 8. MAIN LOOP
// =====================================================

void loop() {

  // Wait until next sending interval
  if (
    millis() - lastSendMs <
    sendIntervalMs
  ) {

    delay(50);
    return;
  }


  lastSendMs = millis();


  // ==================================
  // CHECK WIFI
  // ==================================

  if (WiFi.status() != WL_CONNECTED) {

    Serial.println();
    Serial.println(
      "Wi-Fi disconnected."
    );

    if (!connectWifi()) {

      Serial.println(
        "Skipping this sensor upload."
      );

      return;
    }
  }


  // ==================================
  // SENSOR VALUES
  // ==================================

  float moisture = NAN;
  float temperature = NAN;


  if (useDummyData) {

    // ---------------------------------
    // DUMMY DATA
    // ---------------------------------

    moisture =
        35.0f +
        float(sampleNumber % 25);

    temperature =
        27.0f +
        float(sampleNumber % 12) *
        0.3f;

  } else {

    // ---------------------------------
    // REAL SENSOR DATA
    // ---------------------------------

    moisture =
        readSoilMoisture();

    temperature =
        readTemperature();
  }


  sampleNumber++;


  // ==================================
  // VALIDATE SENSOR VALUES
  // ==================================

  if (
    !isfinite(moisture) ||
    !isfinite(temperature)
  ) {

    Serial.println(
      "Invalid sensor values."
    );

    Serial.println(
      "Upload skipped."
    );

    return;
  }


  // ==================================
  // SEND TO SUPABASE
  // ==================================

  sendSensorData(
    moisture,
    temperature
  );
}
