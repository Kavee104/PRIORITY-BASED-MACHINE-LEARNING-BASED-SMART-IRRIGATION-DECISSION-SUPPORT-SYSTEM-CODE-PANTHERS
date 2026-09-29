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
      return 'http://10.0.2.2:5000';
    }

    return 'http://localhost:5000';
  }

  // Client-safe Supabase values must be supplied at build/run time. Never put
  // a service-role key or device secret in the Flutter application.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get predictIrrigationUrl =>
      '$apiBaseUrl/predict_irrigation';

  static String get predictReleaseUrl =>
      '$apiBaseUrl/api/predict-release';

  static String get realtimeReservoirDataUrl =>
      '$apiBaseUrl/api/realtime-reservoir-data';
}

