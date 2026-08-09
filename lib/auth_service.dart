import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

enum UserRole { farmer, admin }

class UserAccount {
  final int id;
  final String username;
  final String email;
  final String password;
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

  WaterRequest({
    required this.requestID,
    required this.farmerId,
    required this.fieldID,
    required this.zoneName,
    required this.farmerName,
    required this.status,
    required this.requestTime,
  });

  Map<String, dynamic> toJson() => {
        'RequestID': requestID,
        'farmer_id': farmerId,
        'FieldID': fieldID,
        'ZoneName': zoneName,
        'farmer_name': farmerName,
        'Status': status,
        'RequestTime': requestTime,
      };
}

class AuthService {
  static final AuthService instance = AuthService._internal();

  AuthService._internal() {
    _initDefaultAccounts();
  }

  final Map<String, UserAccount> _accounts = {};
  final List<WaterRequest> _waterRequests = [];
  final List<Map<String, dynamic>> _auditLogs = [];
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
  }) {
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} (Just now)";

    final req = WaterRequest(
      requestID: _nextRequestId++,
      farmerId: farmerId,
      fieldID: fieldId,
      zoneName: zoneName,
      farmerName: farmerName,
      status: 'Pending',
      requestTime: timeStr,
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
        return true;
      }
    }
    return false;
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
  }) {
    final cleanUsername = username.trim().toLowerCase();
    final cleanEmail = (email ?? '$cleanUsername@example.com').trim().toLowerCase();

    if (_accounts.containsKey(cleanUsername)) {
      return false;
    }

    UserRole role = roleStr.toLowerCase() == 'admin' ? UserRole.admin : UserRole.farmer;

    final newId = DateTime.now().millisecondsSinceEpoch % 100000;
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

  /// Authenticates user and enforces Role-Based Access Control (RBAC)
  Future<AuthResponse> login({
    required String identifier,
    required String password,
    required UserRole targetRole,
  }) async {
    final cleanIdentifier = identifier.trim().toLowerCase();
    final cleanPassword = password.trim();

    // 1. First check local RBAC database
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

    // 2. Try remote backend if local user not found
    try {
      final response = await http.post(
        Uri.parse("${AppConfig.apiBaseUrl}/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": identifier,
          "password": password,
        }),
      ).timeout(const Duration(seconds: 4));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final user = UserAccount(
          id: data['farmer_id'] ?? data['id'] ?? 999,
          username: identifier,
          email: identifier,
          password: password,
          name: data['name'] ?? identifier,
          role: targetRole,
        );
        addAuditLog(
          action: 'USER_LOGIN',
          user: user.name,
          details: 'Logged in via API backend',
        );
        return AuthResponse(
          success: true,
          message: "Login successful via Backend",
          user: user,
        );
      } else {
        return AuthResponse(
          success: false,
          message: data['error'] ?? "Login failed",
        );
      }
    } catch (_) {
      // Backend unreachable and user not found locally
      return AuthResponse(
        success: false,
        message: "User '$identifier' not found. Available demo accounts:\n• Farmer: farmer / farmer\n• Admin: admin / admin",
      );
    }
  }
}
