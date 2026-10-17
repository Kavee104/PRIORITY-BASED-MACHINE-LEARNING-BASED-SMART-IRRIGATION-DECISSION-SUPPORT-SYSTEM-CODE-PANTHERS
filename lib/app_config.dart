class AppConfig {
  static const String _definedApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  static const String _cloudApiBaseUrl =
      'https://priority-based-machine-learning-based-smart-irri-production.up.railway.app';

  static String get apiBaseUrl {
    if (_definedApiBaseUrl.isNotEmpty) {
      return _definedApiBaseUrl;
    }

    return _cloudApiBaseUrl;
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
