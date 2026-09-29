import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'urgency_score.dart';
import 'water_requirement.dart';

enum UserRole { farmer, admin }

class UserAccount {
  final int id;
  final String username;
  final String email;
  String password;
  final String name;
  final UserRole role;

  UserAccount({
    required this.id,
    required this.username,
    required this.email,
    required this.password,
    required this.name,
    required this.role,
  });

  String get roleString => role.name;
}

class AuthResponse {
  final bool success;
  final String message;
  final UserAccount? user;

  AuthResponse({
    required this.success,
    required this.message,
    this.user,
  });
}

class WaterRequest {
  final int requestID;
  final int farmerId;
  final int fieldID;
  final String zoneName;
  final String farmerName;
  String status; // "Pending", "Approved", "Rejected"
  final String requestTime;
  final int? soilMoisture;
  final double? soilTemperature;
  final double areaAcres;
  final double previousDayRainfall;
  DateTime? approvedAt;

  WaterRequest({
    required this.requestID,
    required this.farmerId,
    required this.fieldID,
    required this.zoneName,
    required this.farmerName,
    required this.status,
    required this.requestTime,
    this.soilMoisture,
    this.soilTemperature,
    this.areaAcres = 2.5,
    this.previousDayRainfall = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'RequestID': requestID,
        'farmer_id': farmerId,
        'FieldID': fieldID,
        'ZoneName': zoneName,
        'farmer_name': farmerName,
        'Status': status,
        'RequestTime': requestTime,
        if (soilMoisture != null) 'SoilMoisture': soilMoisture,
        if (soilTemperature != null) 'SoilTemperature': soilTemperature,
        'AreaAcres': areaAcres,
        'PreviousDayRainfall': previousDayRainfall,
        'ApprovedAt': approvedAt?.toIso8601String(),
      };
}

class AuthService {
  static final AuthService instance = AuthService._internal();
  String? sessionToken;

  AuthService._internal() {
    _initDefaultAccounts();
  }

  final Map<String, UserAccount> _accounts = {};
  final List<WaterRequest> _waterRequests = [];
  final List<Map<String, dynamic>> _auditLogs = [];
  final Map<int, List<Map<String, dynamic>>> _farmerFields = {};
  int _nextRequestId = 101;

  void _initDefaultAccounts() {
    // Seed default role-based accounts (Farmer & Admin)
    _addAccount(UserAccount(
      id: 101,
      username: 'farmer',
      email: 'farmer@example.com',
      password: 'farmer',
      name: 'Farmer User',
      role: UserRole.farmer,
    ));

    _addAccount(UserAccount(
      id: 301,
      username: 'admin',
      email: 'admin@example.com',
      password: 'admin',
      name: 'System Admin',
      role: UserRole.admin,
    ));

    // Seed initial audit log
    addAuditLog(action: 'SYSTEM_INIT', user: 'system', details: 'Smart Irrigation Platform Started');
  }

  // -------------------------------------------------------------------------
  // Farmer Fields (local demo store)
  // -------------------------------------------------------------------------
  List<Map<String, dynamic>> getFarmerFields(int farmerId) {
    if (!_farmerFields.containsKey(farmerId)) {
      _farmerFields[farmerId] = [];
    }
    return List.unmodifiable(_farmerFields[farmerId]!);
  }

  Map<String, dynamic> addFarmerField({required int farmerId, required int zoneNo, required double size, String? cropType}) {
    final existingFields = _farmerFields[farmerId] ?? [];
    final maxFid = existingFields.fold<int>(0, (max, f) {
      final fid = int.tryParse("${f['FieldID']}") ?? 0;
      return fid > max ? fid : max;
    });
    final newId = maxFid + 1;
    final field = {
      "FieldID": newId,
      "ZoneNo": zoneNo,
      "Size": size,
      "CropType": cropType ?? 'General',
      "Moisture": "0%",
      "Status": "Pending",
    };
    _farmerFields.putIfAbsent(farmerId, () => []);
    _farmerFields[farmerId]!.insert(0, field);
    addAuditLog(action: 'FIELD_CREATED', user: 'farmer:$farmerId', details: 'Added field #$newId for farmer $farmerId');
    return field;
  }

  void _addAccount(UserAccount account) {
    _accounts[account.username.toLowerCase()] = account;
    _accounts[account.email.toLowerCase()] = account;
  }

  List<UserAccount> getAllAccounts() {
    final uniqueMap = <int, UserAccount>{};
    for (var acc in _accounts.values) {
      uniqueMap[acc.id] = acc;
    }
    return uniqueMap.values.toList();
  }

  // -------------------------------------------------------------------------
  // Water Requests Real-Time State Management
  // -------------------------------------------------------------------------
  List<WaterRequest> getWaterRequests() => List.unmodifiable(_waterRequests);

  List<WaterRequest> getFarmerRequests(int farmerId) {
    return _waterRequests.where((r) => r.farmerId == farmerId).toList();
  }

  WaterRequest addWaterRequest({
    required int farmerId,
    required int fieldId,
    required String zoneName,
    required String farmerName,
    int? requestId,
    int? moisture,
    double? temperature,
    double? areaAcres,
    double? previousDayRainfall,
  }) {
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} (Just now)";

    final req = WaterRequest(
      requestID: requestId ?? _nextRequestId++,
      farmerId: farmerId,
      fieldID: fieldId,
      zoneName: zoneName,
      farmerName: farmerName,
      status: 'Pending',
      requestTime: timeStr,
      soilMoisture: moisture,
      soilTemperature: temperature,
      areaAcres: areaAcres ?? 2.5,
      previousDayRainfall: previousDayRainfall ?? 0.0,
    );

    _waterRequests.insert(0, req);
    addAuditLog(
      action: 'WATER_REQUEST',
      user: farmerName,
      details: 'Submitted water request #${req.requestID} for $zoneName',
    );
    return req;
  }

  bool approveRequest(int requestId) {
    for (var r in _waterRequests) {
      if (r.requestID == requestId) {
        r.status = 'Approved';
        r.approvedAt = DateTime.now();
        addAuditLog(
          action: 'REQUEST_APPROVED',
          user: 'admin',
          details: 'Approved water request #$requestId for ${r.zoneName}',
        );
        return true;
      }
    }
    return false;
  }

  bool rejectRequest(int requestId) {
    for (var r in _waterRequests) {
      if (r.requestID == requestId) {
        r.status = 'Rejected';
        addAuditLog(
          action: 'REQUEST_REJECTED',
          user: 'admin',
          details: 'Rejected water request #$requestId for ${r.zoneName}',
        );
      }
    }
    return false;
  }

  void clearWaterRequests() {
    _waterRequests.clear();
    addAuditLog(
      action: 'REQUESTS_CLEARED',
      user: 'admin',
      details: 'Cleared all active farmer water requests',
    );
  }

  // -------------------------------------------------------------------------
  // Dynamic Zone Priority Schedule Aggregated from Live Requests
  // -------------------------------------------------------------------------
  String _cleanZoneName(String raw) {
    if (raw.contains('(')) {
      final clean = raw.split('(')[0].trim();
      if (clean.isNotEmpty) return clean;
    }
    return raw.trim();
  }

  List<Map<String, dynamic>> getZonePrioritySchedule() {
    if (_waterRequests.isEmpty) {
      return [];
    }

    final Map<int, DateTime> lastIrrigationByField = {};
    for (final request in _waterRequests) {
      if (request.status == 'Approved' && request.approvedAt != null) {
        final previous = lastIrrigationByField[request.fieldID];
        if (previous == null || request.approvedAt!.isAfter(previous)) {
          lastIrrigationByField[request.fieldID] = request.approvedAt!;
        }
      }
    }

    final Map<String, List<Map<String, dynamic>>> zoneMap = {};
    for (var r in _waterRequests) {
      final zName = _cleanZoneName(r.zoneName);
      if (!zoneMap.containsKey(zName)) {
        zoneMap[zName] = [];
      }
      final requestData = r.toJson();
      final lastIrrigation = lastIrrigationByField[r.fieldID];
      requestData['DaysSinceLastIrrigation'] = lastIrrigation == null
          ? maximumIrrigationIntervalDays
          : DateTime.now().difference(lastIrrigation).inMinutes / 1440.0;
      zoneMap[zName]!.add(requestData);
    }

    final List<Map<String, dynamic>> schedule = [];
    zoneMap.forEach((zName, list) {
      double totalMoist = 0;
      double totalTemp = 0;
      double totalAreaAcres = 0;
      double totalPreviousDayRainfall = 0;
      double totalDaysSinceLastIrrigation = 0;
      for (var item in list) {
        final m = item['SoilMoisture'] ?? item['soil_moisture'] ?? 30.0;
        final t = item['SoilTemperature'] ?? item['soil_temperature'] ?? 29.5;
        final area = item['AreaAcres'] ?? item['Size'] ?? 2.5;
        final rain = item['PreviousDayRainfall'] ?? 0.0;
        final days =
            item['DaysSinceLastIrrigation'] ?? maximumIrrigationIntervalDays;
        totalMoist += (m is num) ? m.toDouble() : 30.0;
        totalTemp += (t is num) ? t.toDouble() : 29.5;
        totalAreaAcres += (area is num) ? area.toDouble() : 2.5;
        totalPreviousDayRainfall += (rain is num) ? rain.toDouble() : 0.0;
        totalDaysSinceLastIrrigation += (days is num)
            ? days.toDouble()
            : maximumIrrigationIntervalDays;
      }

      final avgMoist = (totalMoist / list.length).roundToDouble();
      final avgTemp = double.parse((totalTemp / list.length).toStringAsFixed(1));
      final avgPreviousDayRainfall = totalPreviousDayRainfall / list.length;
      final avgDaysSinceLastIrrigation =
          totalDaysSinceLastIrrigation / list.length;

      final urgencyScore = double.parse(
        calculateUrgencyScore(
          soilMoisture: avgMoist,
          temperature: avgTemp,
          daysSinceLastIrrigation: avgDaysSinceLastIrrigation,
        ).toStringAsFixed(1),
      );
      final int targetWaterLiters = calculateTargetWaterRequirementLiters(
        soilMoisture: avgMoist,
        temperature: avgTemp,
        previousDayRainfall: avgPreviousDayRainfall,
        areaAcres: totalAreaAcres,
      ).round();

      schedule.add({
        'ZoneName': zName,
        'TotalFields': list.length,
        'TotalAreaAcres': double.parse(totalAreaAcres.toStringAsFixed(1)),
        'AvgSoilMoisture': avgMoist,
        'AvgSoilTemp': avgTemp,
        'AvgDaysSinceLastIrrigation': avgDaysSinceLastIrrigation,
        'urgency_score': urgencyScore,
        'target_water_req_liters': targetWaterLiters,
        'PredictedVolume': targetWaterLiters,
        'PreviousDayRainfall': avgPreviousDayRainfall,
        'Date': 'Today',
        'Explanation': '[Zone Consolidated] ${list.length} active field requests grouped into $zName. Zone Avg Moisture: $avgMoist%, Zone Avg Temp: $avgTemp°C, Avg Days Since Irrigation: ${avgDaysSinceLastIrrigation.toStringAsFixed(1)}, Previous-day Rainfall: ${avgPreviousDayRainfall.toStringAsFixed(1)} mm, Area: ${totalAreaAcres.toStringAsFixed(1)} acres. Urgency Score: $urgencyScore (Formula 1). Target Water Needed: $targetWaterLiters L (Formula 2).',
      });
    });

    schedule.sort((a, b) => (b['urgency_score'] as double).compareTo(a['urgency_score'] as double));

    for (int i = 0; i < schedule.length; i++) {
      schedule[i]['Rank'] = i + 1;
    }

    return schedule;
  }

  // -------------------------------------------------------------------------
  // Audit Trail State
  // -------------------------------------------------------------------------
  void addAuditLog({required String action, required String user, required String details}) {
    final now = DateTime.now();
    final timestamp = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    _auditLogs.insert(0, {
      'timestamp': timestamp,
      'action': action,
      'user': user,
      'details': details,
    });
  }

  List<Map<String, dynamic>> getAuditLogs() => List.unmodifiable(_auditLogs);

  // -------------------------------------------------------------------------
  // Registration & Authentication
  // -------------------------------------------------------------------------
  bool registerAccount({
    required String username,
    required String password,
    required String roleStr,
    String? email,
    String? name,
    int? customId,
  }) {
    final cleanUsername = username.trim().toLowerCase();
    final cleanEmail = (email ?? '$cleanUsername@example.com').trim().toLowerCase();

    if (_accounts.containsKey(cleanUsername)) {
      return false;
    }

    UserRole role = roleStr.toLowerCase() == 'admin' ? UserRole.admin : UserRole.farmer;

    final newId = customId ?? (DateTime.now().millisecondsSinceEpoch % 100000);
    final account = UserAccount(
      id: newId,
      username: username.trim(),
      email: cleanEmail,
      password: password.trim(),
      name: name ?? username.trim(),
      role: role,
    );

    _addAccount(account);
    addAuditLog(
      action: 'USER_CREATED',
      user: 'admin',
      details: 'Created user "${account.username}" with ${role.name.toUpperCase()} role',
    );
    return true;
  }

  bool changePassword({
    required int userId,
    String? userEmail,
    required String oldPassword,
    required String newPassword,
  }) {
    final cleanOld = oldPassword.trim();
    final cleanNew = newPassword.trim();
    final cleanEmail = (userEmail ?? '').trim().toLowerCase();

    for (var account in _accounts.values) {
      if (account.id == userId ||
          (cleanEmail.isNotEmpty &&
              (account.email.toLowerCase() == cleanEmail ||
                  account.username.toLowerCase() == cleanEmail))) {
        if (account.password != cleanOld) {
          return false;
        }
        account.password = cleanNew;
        addAuditLog(
          action: 'PASSWORD_CHANGED',
          user: account.name,
          details: 'Updated account password',
        );
        return true;
      }
    }
    return false;
  }

  /// Authenticates user and enforces Role-Based Access Control (RBAC)
  Future<AuthResponse> login({
    required String identifier,
    required String password,
    required UserRole targetRole,
  }) async {
    final cleanIdentifier = identifier.trim().toLowerCase();
    final cleanPassword = password.trim();
    sessionToken = null;

    // A backend session provides the farmer identity for owner-scoped IoT data.
    // Keep the existing local demo account path as an offline fallback.
    try {
      final response = await http.post(
        Uri.parse("${AppConfig.apiBaseUrl}/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": identifier, "password": password}),
      ).timeout(const Duration(seconds: 4));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final serverRole = data['role'] == 'admin' ? UserRole.admin : UserRole.farmer;
        if (serverRole != targetRole && serverRole != UserRole.admin) {
          return AuthResponse(success: false, message: 'Access denied for this role');
        }
        final user = UserAccount(
          id: data['farmer_id'] ?? data['id'] ?? 999,
          username: identifier,
          email: data['email'] ?? identifier,
          password: password,
          name: data['name'] ?? identifier,
          role: serverRole,
        );
        sessionToken = data['session_token'] as String?;
        _addAccount(user);
        return AuthResponse(success: true, message: 'Login successful', user: user);
      }
    } catch (_) {
      // A local demo account can still be used when the backend is offline.
    }

    // Existing in-memory demo accounts.
    if (_accounts.containsKey(cleanIdentifier)) {
      final account = _accounts[cleanIdentifier]!;
      if (account.password == cleanPassword) {
        // Enforce Role-Based Access Control (RBAC)
        if (account.role == targetRole || account.role == UserRole.admin) {
          addAuditLog(
            action: 'USER_LOGIN',
            user: account.name,
            details: 'Logged in to ${account.roleString.toUpperCase()} portal',
          );
          return AuthResponse(
            success: true,
            message: "Login successful (${account.roleString.toUpperCase()} Role Verified)",
            user: account,
          );
        } else {
          return AuthResponse(
            success: false,
            message: "Access Denied (RBAC): Account '${account.username}' has ${account.roleString.toUpperCase()} role and cannot access ${targetRole.name.toUpperCase()} portal.",
          );
        }
      } else {
        return AuthResponse(
          success: false,
          message: "Invalid password for user '$cleanIdentifier'",
        );
      }
    }

    return AuthResponse(
      success: false,
      message: "Invalid credentials or backend unavailable for '$identifier'",
    );
  }
}
