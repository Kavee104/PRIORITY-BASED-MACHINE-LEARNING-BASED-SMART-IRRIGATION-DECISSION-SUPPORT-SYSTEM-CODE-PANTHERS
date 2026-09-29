import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

class SensorReadingSnapshot {
  const SensorReadingSnapshot({
    required this.deviceId,
    required this.farmerId,
    required this.zoneNo,
    required this.deviceName,
    required this.moisture,
    required this.temperature,
    required this.recordedAt,
    required this.lastSeen,
    required this.online,
  });

  final String deviceId;
  final int? farmerId;
  final int? zoneNo;
  final String? deviceName;
  final num? moisture;
  final double? temperature;
  final DateTime? recordedAt;
  final DateTime? lastSeen;
  final bool online;

  DateTime? get lastUpdated => recordedAt ?? lastSeen;

  Map<String, dynamic> toDashboardMap() => {
    'deviceId': deviceId,
    'farmerId': farmerId,
    'farmerName': farmerId == null ? 'Unassigned' : 'Farmer $farmerId',
    'zoneNo': zoneNo,
    'deviceName': deviceName,
    'moisture': moisture,
    'temperature': temperature,
    'recordedAt': recordedAt?.toIso8601String(),
    'lastSeen': lastUpdated?.toIso8601String(),
    'deviceStatus': online ? 'ONLINE' : 'OFFLINE',
    'source': 'supabase',
  };
}

class SupabaseSensorService {
  SupabaseSensorService._(this._client);

  static const Duration onlineThreshold = Duration(seconds: 30);
  static bool _initialized = false;

  final SupabaseClient _client;

  static bool get isAvailable => _initialized;

  static Future<bool> initialize() async {
    if (!AppConfig.hasSupabaseConfig) return false;

    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  static SupabaseSensorService? get instance =>
      _initialized ? SupabaseSensorService._(Supabase.instance.client) : null;

  Future<SensorReadingSnapshot?> getLatestReadingForFarmer(int farmerId) async {
    final device = await _client
        .from('iot_devices')
        .select('device_id, farmer_id, zone_no, device_name, last_seen')
        .eq('farmer_id', farmerId)
        .eq('active', true)
        .order('zone_no')
        .limit(1)
        .maybeSingle();

    if (device == null) return null;
    return _withLatestReading(Map<String, dynamic>.from(device));
  }

  Future<List<SensorReadingSnapshot>> getAllLatestDeviceReadings() async {
    final response = await _client
        .from('iot_devices')
        .select('device_id, farmer_id, zone_no, device_name, last_seen')
        .eq('active', true)
        .order('zone_no');

    final devices = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    // Each device fetch is limited to one row, so polling never downloads the
    // sensor history. The requests run concurrently for small prototype fleets.
    return Future.wait(devices.map(_withLatestReading));
  }

  Future<SensorReadingSnapshot> _withLatestReading(
    Map<String, dynamic> device,
  ) async {
    final deviceId = device['device_id'].toString();
    final reading = await _client
        .from('sensor_readings')
        .select('moisture, temperature, recorded_at')
        .eq('device_id', deviceId)
        .order('recorded_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final lastSeen = _dateTime(device['last_seen']);
    final now = DateTime.now().toUtc();
    final online =
        lastSeen != null && !lastSeen.isBefore(now.subtract(onlineThreshold));

    return SensorReadingSnapshot(
      deviceId: deviceId,
      farmerId: _integer(device['farmer_id']),
      zoneNo: _integer(device['zone_no']),
      deviceName: device['device_name']?.toString(),
      moisture: reading?['moisture'] as num?,
      temperature: (reading?['temperature'] as num?)?.toDouble(),
      recordedAt: _dateTime(reading?['recorded_at']),
      lastSeen: lastSeen,
      online: online,
    );
  }

  static int? _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  static DateTime? _dateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}
