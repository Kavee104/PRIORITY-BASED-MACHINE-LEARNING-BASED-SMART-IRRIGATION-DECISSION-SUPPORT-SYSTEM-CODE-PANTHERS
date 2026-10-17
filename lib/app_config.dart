import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _definedApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  static String get apiBaseUrl {
    if (_definedApiBaseUrl.isNotEmpty) {
      return _definedApiBaseUrl;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Physical phone and development laptop must use the same Wi-Fi network.
      // Override this at run time if the laptop receives a different LAN IP.
      return 'http://172.31.98.224:5000';
    }

    return 'http://localhost:5000';
  }

  // These project defaults are client-safe public values. They can still be
  // overridden at build/run time. Never put a service-role key or device
  // secret in the Flutter application.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bsmhjdwtbpbhlktjmocj.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_1kgHrzhwsGkpUL3bNS0EBg_Jd42jPvD',
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get predictIrrigationUrl => '$apiBaseUrl/predict_irrigation';

  static String get predictReleaseUrl => '$apiBaseUrl/api/predict-release';

  static String get realtimeReservoirDataUrl =>
      '$apiBaseUrl/api/realtime-reservoir-data';
}
