# ESP8266 NodeMCU sensor client

Board: **NodeMCU 1.0 (ESP-12E Module)** (`esp8266:esp8266:nodemcuv2`).

Wiring:

- Capacitive soil sensor `AO` to `A0`
- DS18B20 `DATA` to `D2` / GPIO4
- DS18B20 4.7 kOhm pull-up resistor between `DATA` and `3.3V`
- All grounds connected

Before uploading, copy `device_secrets.example.h` to `device_secrets.h` and
enter the Wi-Fi values and registered device secret. The local secret file is
ignored by Git.

The NodeMCU development board normally includes an A0 voltage divider, but
verify the exact board's permitted A0 voltage before connecting the soil
sensor. A bare ESP8266 ADC accepts only about 1.0 V.

Compile/upload with Arduino IDE using **NodeMCU 1.0 (ESP-12E Module)**, select
the detected COM port, then open Serial Monitor at 115200 baud. A successful
cloud write prints `HTTP status: 201`.
