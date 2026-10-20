import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'app_localization.dart';
import 'app_theme.dart';
import 'auth_service.dart';
import 'main.dart';
import 'user_management_screen.dart';
import 'priority_schedule_screen.dart';
import 'water_requirement.dart';
import 'water_release_prediction_card.dart';
import 'supabase_sensor_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String adminName;

  const AdminDashboardScreen({super.key, required this.adminName});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final String baseUrl = AppConfig.apiBaseUrl;

  Map<String, String> get _adminHeaders {
    final token = AuthService.instance.sessionToken;
    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  String _selectedNavItem = 'Dashboard';
  bool _isLoading = true;

  // Stats from API
  Map<String, dynamic> _stats = {};

  // Water requests from API
  List<dynamic> _waterRequests = [];
  bool _hasCloudWaterRequests = false;
  static const int _requestsPerPage = 5;
  int _requestPage = 0;

  // Audit log from API
  List<dynamic> _auditLog = [];

  // Users from API
  List<dynamic> _apiUsers = [];

  // Action in progress tracking
  int? _actionInProgressId;

  // Sensor Data Telemetry
  List<dynamic> _zoneSensors = [];
  String? _sensorError;
  Timer? _sensorTimer;
  bool _sensorFetchInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _sensorTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchZoneSensors();
      _fetchWaterRequests();
    });
  }

  @override
  void dispose() {
    _sensorTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    await Future.wait([
      _fetchWaterRequests(),
      _fetchAuditLog(),
      _fetchUsers(),
      _fetchZoneSensors(),
    ]);

    await _fetchStats();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchZoneSensors() async {
    if (_sensorFetchInProgress) return;
    _sensorFetchInProgress = true;

    final cloudService = SupabaseSensorService.instance;
    if (cloudService != null) {
      try {
        final readings = await cloudService.getAllLatestDeviceReadings();
        if (!mounted) return;
        setState(() {
          _zoneSensors = readings
              .map((reading) => reading.toDashboardMap())
              .toList();
          _sensorError = null;
        });
        _sensorFetchInProgress = false;
        return;
      } catch (_) {
        // Keep the existing Flask endpoint as a fallback for cloud failures.
      }
    }

    await _fetchZoneSensorsFromFlask();
  }

  Future<void> _fetchZoneSensorsFromFlask() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/admin/sensors'), headers: _adminHeaders)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _zoneSensors = data['sensors'] ?? [];
          _sensorError = null;
        });
      } else {
        setState(
          () => _sensorError = 'IoT data unavailable (${response.statusCode})',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _sensorError = 'IoT backend unreachable');
    } finally {
      _sensorFetchInProgress = false;
    }
  }

  Future<void> _fetchStats() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/stats'), headers: _adminHeaders)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) _stats = data['stats'] ?? {};
      }
    } catch (_) {}

    if (mounted) {
      final combinedUsers = _getCombinedUsers();
      final allRequests = _getCombinedRequests();
      final pendingCount = allRequests
          .where((r) => r['Status'] == 'Pending')
          .length;
      final approvedCount = allRequests
          .where((r) => r['Status'] == 'Approved')
          .length;
      final rejectedCount = allRequests
          .where((r) => r['Status'] == 'Rejected')
          .length;

      final farmerCount = combinedUsers
          .where((u) => u['role'].toString().toLowerCase() == 'farmer')
          .length;
      final officerCount = combinedUsers
          .where((u) => u['role'].toString().toLowerCase() == 'officer')
          .length;
      final adminCount = combinedUsers
          .where((u) => u['role'].toString().toLowerCase() == 'admin')
          .length;

      setState(() {
        _stats = {
          'total_users': combinedUsers.length,
          'farmers': farmerCount,
          'officers': officerCount,
          'admins': adminCount,
          'total_requests': allRequests.length,
          'pending_requests': pendingCount,
          'approved_requests': approvedCount,
          'rejected_requests': rejectedCount,
        };
      });
    }
  }

  List<dynamic> _getCombinedRequests() {
    // Once the backend has responded, its MySQL rows are authoritative.
    // Mixing in local demo/fallback requests creates fake Farmer #101-style
    // rows in the admin dashboard.
    final list = _hasCloudWaterRequests
        ? List<dynamic>.from(_waterRequests)
        : AuthService.instance
              .getWaterRequests()
              .map((request) => request.toJson())
              .toList();
    list.sort((a, b) {
      final timeA = (a['RequestTime'] ?? '').toString();
      final timeB = (b['RequestTime'] ?? '').toString();
      if (timeA.isNotEmpty && timeB.isNotEmpty) {
        final cmp = timeB.compareTo(
          timeA,
        ); // Compare timestamps descending (newest time at top)
        if (cmp != 0) return cmp;
      }
      final idA = (a['RequestID'] ?? 0) as int;
      final idB = (b['RequestID'] ?? 0) as int;
      return idB.compareTo(idA);
    });
    return list;
  }

  int? _intValue(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  int? _requestZoneNo(dynamic request) {
    final explicitZone = _intValue(request['ZoneNo']);
    if (explicitZone != null) return explicitZone;
    final match = RegExp(
      r'Zone\s+(\d+)',
      caseSensitive: false,
    ).firstMatch('${request['ZoneName'] ?? ''}');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Map<String, dynamic>? _liveSensorForRequest(dynamic request) {
    final farmerId = _intValue(request['farmer_id'] ?? request['FarmerID']);
    final zoneNo = _requestZoneNo(request);
    if (farmerId == null || zoneNo == null) return null;

    for (final item in _zoneSensors) {
      if (item is! Map) continue;
      final sensor = Map<String, dynamic>.from(item);
      if (_intValue(sensor['farmerId']) == farmerId &&
          _intValue(sensor['zoneNo']) == zoneNo) {
        return sensor;
      }
    }
    return null;
  }

  void _clearWaterRequests() {
    if (_waterRequests.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: 26,
            ),
            SizedBox(width: 10),
            Text("Clear All Requests?"),
          ],
        ),
        content: const Text(
          "Are you sure you want to clear the water requests table? All current request rows will be cleared.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final response = await http
                    .post(
                      Uri.parse('$baseUrl/admin/clear-requests'),
                      headers: _adminHeaders,
                    )
                    .timeout(const Duration(seconds: 20));
                final body = jsonDecode(response.body);
                if (response.statusCode != 200) {
                  throw Exception(
                    body['message'] ?? 'Could not clear the requests table.',
                  );
                }

                AuthService.instance.clearWaterRequests();
                if (!mounted) return;
                setState(() {
                  _waterRequests = [];
                  _requestPage = 0;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      body['deleted_count'] == null
                          ? 'Water requests table cleared successfully.'
                          : '${body['deleted_count']} request(s) cleared successfully.',
                    ),
                    backgroundColor: AppColors.primaryGreen,
                  ),
                );
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error.toString().replaceFirst('Exception: ', ''),
                    ),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text("Clear All"),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getCombinedUsers() {
    final userMap = <String, Map<String, dynamic>>{};

    // Cloud accounts are authoritative. Local demo accounts are only a
    // fallback while the backend is unavailable.
    if (_apiUsers.isNotEmpty) {
      for (var u in _apiUsers) {
        final uname = (u['username'] ?? u['email'] ?? '').toString().trim();
        if (uname.isEmpty) continue;
        final id = u['id']?.toString().trim();
        final email = u['email']?.toString().trim().toLowerCase();
        final key = id != null && id.isNotEmpty
            ? '${u['role'] ?? 'farmer'}:$id'
            : (email?.isNotEmpty == true ? email! : uname.toLowerCase());
        userMap[key] = {
          'id': u['id'],
          'username': uname,
          'email': u['email'] ?? '',
          'name': u['name'] ?? uname,
          'role': (u['role'] ?? 'farmer').toString(),
        };
      }
      return userMap.values.toList();
    }

    for (var account in AuthService.instance.getAllAccounts()) {
      final key = '${account.roleString}:${account.id}';
      userMap[key] = {
        'id': account.id,
        'username': account.username,
        'email': account.email,
        'name': account.name,
        'role': account.roleString,
      };
    }

    return userMap.values.toList();
  }

  Future<void> _fetchWaterRequests() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/admin/water-requests'),
            headers: _adminHeaders,
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        final requests = List<dynamic>.from(data['requests'] ?? const []);
        setState(() {
          _hasCloudWaterRequests = true;
          _waterRequests = requests;
          final pageCount = (_waterRequests.length / _requestsPerPage).ceil();
          if (pageCount == 0) {
            _requestPage = 0;
          } else if (_requestPage >= pageCount) {
            _requestPage = pageCount - 1;
          }
        });
        return;
      }
    } catch (_) {}

    // Local requests are used only when this screen has never received a
    // successful cloud response. A temporary network error must not replace
    // already-loaded MySQL data with local demo data.
    if (mounted && !_hasCloudWaterRequests) {
      setState(() {
        _waterRequests = _getCombinedRequests();
      });
    }
  }

  Future<void> _fetchAuditLog() async {
    List<dynamic> remoteLog = [];
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/audit-log'), headers: _adminHeaders)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        remoteLog = data['log'] ?? [];
      }
    } catch (_) {}

    final localLog = AuthService.instance.getAuditLogs();
    final combined = [...localLog, ...remoteLog];
    if (mounted) {
      setState(() {
        _auditLog = combined;
      });
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/users'), headers: _adminHeaders)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) setState(() => _apiUsers = data['users'] ?? []);
      }
    } catch (_) {
      if (mounted) {
        final accounts = AuthService.instance.getAllAccounts();
        setState(() {
          _apiUsers = accounts
              .map((a) => {'username': a.username, 'role': a.roleString})
              .toList();
        });
      }
    }
  }

  Future<void> _approveRequest(int requestId) async {
    setState(() => _actionInProgressId = requestId);
    AuthService.instance.approveRequest(requestId);
    try {
      await http
          .post(
            Uri.parse('$baseUrl/admin/water-requests/$requestId/approve'),
            headers: _adminHeaders,
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {}

    await _loadAllData();
    if (mounted) {
      setState(() => _actionInProgressId = null);
      _showMessage('Request #$requestId approved!', AppColors.primaryGreen);
    }
  }

  Future<void> _rejectRequest(int requestId) async {
    setState(() => _actionInProgressId = requestId);
    AuthService.instance.rejectRequest(requestId);
    try {
      await http
          .post(
            Uri.parse('$baseUrl/admin/water-requests/$requestId/reject'),
            headers: _adminHeaders,
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {}

    await _loadAllData();
    if (mounted) {
      setState(() => _actionInProgressId = null);
      _showMessage('Request #$requestId rejected', AppColors.danger);
    }
  }

  void _showMessage(String message, [Color? color]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: color ?? AppColors.primaryDarkGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final navItems = [
      {'icon': Icons.admin_panel_settings_rounded, 'title': 'Dashboard'},
      {'icon': Icons.list_alt_rounded, 'title': 'Priority Schedule'},
      {
        'icon': Icons.supervised_user_circle_rounded,
        'title': 'User Management',
      },
    ];

    return Container(
      width: 260,
      decoration: const BoxDecoration(color: AppColors.primaryDarkGreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Smart Irrigation'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      context.tr('ADMIN CONTROL'),
                      style: const TextStyle(
                        color: AppColors.lightGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: navItems.map((item) {
                final title = item['title'] as String;
                final isSelected = _selectedNavItem == title;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    leading: Icon(
                      item['icon'] as IconData,
                      color: isSelected ? Colors.white : Colors.white70,
                      size: 22,
                    ),
                    title: Text(
                      context.tr(title),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      if (title == 'Priority Schedule') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PriorityScheduleScreen(),
                          ),
                        );
                      } else if (title == 'User Management') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UserManagementScreen(),
                          ),
                        );
                      } else {
                        setState(() => _selectedNavItem = title);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 18,
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: AppColors.primaryDarkGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.adminName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        context.tr('SYSTEM ADMIN'),
                        style: const TextStyle(
                          color: AppColors.lightGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;
    final isCompact = screenWidth < 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: isDesktop ? null : Drawer(child: _buildSidebar(context)),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: isCompact ? 64 : 72,
        automaticallyImplyLeading: !isDesktop,
        title: Row(
          children: [
            if (!isDesktop) ...[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: AppColors.primaryDarkGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Admin Control Center'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryText,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    context.tr(
                      'Real-time System Administration & Water Approval',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        actions: [
          const Center(child: LanguageSelector()),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppColors.secondaryText,
            ),
            tooltip: context.tr('Refresh Data'),
            onPressed: _loadAllData,
          ),
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: AppColors.secondaryText,
            ),
            tooltip: context.tr('Logout'),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
          SizedBox(width: isCompact ? 0 : 8),
        ],
      ),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(context),
          Expanded(
            child: SafeArea(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryGreen,
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.primaryGreen,
                      onRefresh: _loadAllData,
                      child: ListView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 16 : 24,
                          vertical: isCompact ? 16 : 24,
                        ),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1400),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildHeroBanner(),
                                  SizedBox(height: isCompact ? 22 : 28),
                                  _buildMetricsSection(),
                                  SizedBox(height: isCompact ? 24 : 32),
                                  const WaterReleasePredictionCard(),
                                  SizedBox(height: isCompact ? 24 : 32),
                                  _buildZoneSensorsSection(),
                                  SizedBox(height: isCompact ? 24 : 32),
                                  _buildWaterRequestsSection(),
                                  SizedBox(height: isCompact ? 24 : 32),
                                  _buildAuditTrailSection(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Hero Banner
  // -------------------------------------------------------------------------
  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 20 : 28),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDarkGreen.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.brightGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  "SYSTEM GOVERNANCE • LIVE DATA",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Welcome, ${widget.adminName} 👋',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'Real-time water request approvals, user management, and system audit trail.',
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Dynamic Metrics Section (API-driven)
  // -------------------------------------------------------------------------
  Widget _buildMetricsSection() {
    final totalUsers = _stats['total_users'] ?? 0;
    final pendingReqs = _stats['pending_requests'] ?? 0;
    final approvedReqs = _stats['approved_requests'] ?? 0;
    final rejectedReqs = _stats['rejected_requests'] ?? 0;
    final totalReqs = _stats['total_requests'] ?? 0;

    final farmerCnt = _stats['farmers'] ?? 0;
    final adminCnt = _stats['admins'] ?? 0;
    final userSubtitle =
        "${farmerCnt == 1 ? '1 Farmer' : '$farmerCnt Farmers'}, ${adminCnt == 1 ? '1 Admin' : '$adminCnt Admins'}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('System Metrics (Live)'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryText,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final colCount = constraints.maxWidth >= 1100
                ? 5
                : constraints.maxWidth >= 700
                ? 3
                : constraints.maxWidth >= 320
                ? 2
                : 1;
            return GridView.count(
              crossAxisCount: colCount,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisExtent: constraints.maxWidth < 700 ? 148 : 142,
              children: [
                _MetricStatCard(
                  icon: Icons.people_rounded,
                  title: context.tr('Total Users'),
                  value: "$totalUsers",
                  badgeText: context.tr('Live'),
                  badgeColor: AppColors.primaryGreen,
                  subtitle: userSubtitle,
                  iconColor: AppColors.primaryDarkGreen,
                ),
                _MetricStatCard(
                  icon: Icons.pending_actions_rounded,
                  title: context.tr('Pending Requests'),
                  value: "$pendingReqs",
                  badgeText: context.tr(
                    pendingReqs > 0 ? 'Action Needed' : 'Clear',
                  ),
                  badgeColor: pendingReqs > 0
                      ? AppColors.warning
                      : AppColors.primaryGreen,
                  subtitle: context.tr('Awaiting approval'),
                  iconColor: AppColors.warning,
                ),
                _MetricStatCard(
                  icon: Icons.check_circle_rounded,
                  title: context.tr('Approved'),
                  value: "$approvedReqs",
                  badgeText: context.tr('Done'),
                  badgeColor: AppColors.primaryGreen,
                  subtitle: context.tr('Water allocated'),
                  iconColor: AppColors.primaryGreen,
                ),
                _MetricStatCard(
                  icon: Icons.cancel_rounded,
                  title: context.tr('Rejected'),
                  value: "$rejectedReqs",
                  badgeText: context.tr(rejectedReqs > 0 ? 'Declined' : 'None'),
                  badgeColor: rejectedReqs > 0
                      ? AppColors.danger
                      : AppColors.primaryGreen,
                  subtitle: context.tr('Requests denied'),
                  iconColor: AppColors.danger,
                ),
                _MetricStatCard(
                  icon: Icons.water_drop_rounded,
                  title: context.tr('Total Requests'),
                  value: "$totalReqs",
                  badgeText: context.tr('All Time'),
                  badgeColor: AppColors.teal,
                  subtitle: context.tr('Water allocation requests'),
                  iconColor: AppColors.teal,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Water Requests with Approve/Reject Actions
  // -------------------------------------------------------------------------
  Widget _buildZoneSensorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Zone ESP32 Sensors'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryText,
          ),
        ),
        const SizedBox(height: 12),
        if (_sensorError != null)
          Text(_sensorError!, style: const TextStyle(color: AppColors.danger))
        else if (_zoneSensors.isEmpty)
          Text(context.tr('No ESP32 devices registered yet.'))
        else
          ..._zoneSensors.map((item) {
            final sensor = item as Map<String, dynamic>;
            final online = sensor['deviceStatus'] == 'ONLINE';
            final moisture = sensor['moisture'];
            final temperature = sensor['temperature'];
            return Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Zone ${sensor['zoneNo']} · ${sensor['farmerName']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Device: ${sensor['deviceId']}'),
                    Text('Moisture: ${moisture == null ? '--' : '$moisture%'}'),
                    Text(
                      'Temperature: ${temperature == null ? '--' : '$temperature°C'}',
                    ),
                    Text(
                      context.tr(online ? 'ONLINE' : 'OFFLINE'),
                      style: TextStyle(
                        color: online
                            ? AppColors.primaryGreen
                            : AppColors.danger,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('Last updated: ${sensor['lastSeen'] ?? 'Never'}'),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildWaterRequestsSection() {
    final pageCount = (_waterRequests.length / _requestsPerPage).ceil();
    final safePage = pageCount == 0 ? 0 : _requestPage.clamp(0, pageCount - 1);
    final pageStart = safePage * _requestsPerPage;
    final pageEnd = (pageStart + _requestsPerPage).clamp(
      0,
      _waterRequests.length,
    );
    final pageRequests = _waterRequests.sublist(pageStart, pageEnd);

    final requestActions = <Widget>[
      if (_waterRequests.isNotEmpty) ...[
        OutlinedButton.icon(
          onPressed: _clearWaterRequests,
          icon: const Icon(
            Icons.delete_outline_rounded,
            size: 15,
            color: AppColors.danger,
          ),
          label: Text(
            context.tr('Clear Table'),
            style: const TextStyle(fontSize: 12, color: AppColors.danger),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.danger),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.lightGreen,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          "${_waterRequests.length} Requests",
          style: const TextStyle(
            color: AppColors.primaryDarkGreen,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Text(
              context.tr('Farmer Water Requests'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryText,
              ),
            );

            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: requestActions,
            );

            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 12), actions],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                title,
                const SizedBox(width: 16),
                Flexible(child: actions),
              ],
            );
          },
        ),
        const SizedBox(height: 14),

        if (_waterRequests.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.water_drop_outlined,
                  size: 48,
                  color: AppColors.mutedText,
                ),
                SizedBox(height: 12),
                Text(
                  "No water requests yet",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryText,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "When farmers submit water allocation requests, they will appear here for approval.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mutedText, fontSize: 13),
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    AppColors.inputBackground,
                  ),
                  columns: const [
                    DataColumn(
                      label: Text(
                        "Req #",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Farmer",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Zone / Field",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Soil Moisture (Sensor)",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Soil Temp (Sensor)",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Target Water Req (L)",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Requested At",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Status",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "Actions",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                  ],
                  rows: pageRequests.map<DataRow>((r) {
                    final status = (r['Status'] ?? 'Pending') as String;
                    final reqId = r['RequestID'] as int;
                    final isPending = status == 'Pending';
                    final isApproved = status == 'Approved';
                    final isRejected = status == 'Rejected';
                    final isProcessing = _actionInProgressId == reqId;

                    Color sColor = AppColors.warning;
                    Color sBg = Colors.amber.withValues(alpha: 0.15);
                    if (isApproved) {
                      sColor = AppColors.primaryGreen;
                      sBg = AppColors.lightGreen;
                    } else if (isRejected) {
                      sColor = AppColors.danger;
                      sBg = Colors.red.withValues(alpha: 0.1);
                    }

                    final rawZone = "${r['ZoneName'] ?? ''}";
                    final fieldLabel =
                        (!rawZone.contains("Field #") && r['FieldID'] != null)
                        ? "$rawZone (Field #${r['FieldID']})"
                        : rawZone;

                    // New requests contain an immutable request-time snapshot.
                    // For older rows created before snapshots were supported,
                    // show the matching admin-side zone sensor as a fallback.
                    final liveSensor = _liveSensorForRequest(r);
                    final moistNum =
                        r['SoilMoisture'] ??
                        r['soil_moisture'] ??
                        liveSensor?['moisture'];
                    final int? moistVal = (moistNum is num)
                        ? moistNum.toInt()
                        : null;
                    final bool isDryDemand = moistVal != null && moistVal < 35;

                    final tempNum =
                        r['SoilTemperature'] ??
                        r['soil_temperature'] ??
                        liveSensor?['temperature'];
                    final double? tempVal = (tempNum is num)
                        ? tempNum.toDouble()
                        : null;

                    final rainNum = r['PreviousDayRainfall'] ?? 0.0;
                    final areaNum = r['AreaAcres'] ?? r['Size'] ?? 2.5;
                    final double? targetWaterLiters =
                        moistVal != null && tempVal != null
                        ? calculateTargetWaterRequirementLiters(
                            soilMoisture: moistVal.toDouble(),
                            temperature: tempVal,
                            previousDayRainfall: rainNum is num
                                ? rainNum.toDouble()
                                : 0.0,
                            areaAcres: areaNum is num
                                ? areaNum.toDouble()
                                : 2.5,
                          )
                        : null;

                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            "#$reqId",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(Text("${r['farmer_name'] ?? 'Unknown'}")),
                        DataCell(
                          Text(
                            '$fieldLabel\n${r['DeviceID'] ?? liveSensor?['deviceId'] ?? 'No sensor reading'}',
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDryDemand
                                  ? Colors.orange.withValues(alpha: 0.12)
                                  : AppColors.teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    (isDryDemand
                                            ? Colors.orange
                                            : AppColors.teal)
                                        .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.water_drop_rounded,
                                  size: 14,
                                  color: isDryDemand
                                      ? Colors.orange.shade800
                                      : AppColors.teal,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  moistVal == null
                                      ? 'No snapshot'
                                      : "$moistVal% ${isDryDemand ? '(High Need)' : '(Optimal)'}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: isDryDemand
                                        ? Colors.orange.shade900
                                        : AppColors.primaryDarkGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.deepOrange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.thermostat_rounded,
                                  size: 14,
                                  color: Colors.deepOrange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tempVal == null
                                      ? 'No snapshot'
                                      : "${tempVal.toStringAsFixed(1)} °C",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Colors.deepOrange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.water_rounded,
                                  size: 14,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  targetWaterLiters == null
                                      ? '--'
                                      : "${targetWaterLiters.toStringAsFixed(0)} L",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(Text("${r['RequestTime'] ?? ''}")),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: sBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              context.tr(status),
                              style: TextStyle(
                                color: sColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryGreen,
                                  ),
                                )
                              : isPending
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.primaryGreen,
                                        size: 22,
                                      ),
                                      tooltip: context.tr('Approve'),
                                      onPressed: () => _approveRequest(reqId),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.cancel_rounded,
                                        color: AppColors.danger,
                                        size: 22,
                                      ),
                                      tooltip: context.tr('Reject'),
                                      onPressed: () => _rejectRequest(reqId),
                                    ),
                                  ],
                                )
                              : Text(
                                  isApproved ? "✅ Done" : "❌ Denied",
                                  style: TextStyle(
                                    color: isApproved
                                        ? AppColors.primaryGreen
                                        : AppColors.danger,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        if (_waterRequests.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: safePage > 0
                    ? () => setState(() => _requestPage = safePage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Flexible(
                child: Text(
                  'Page ${safePage + 1} of $pageCount  '
                  '(${pageStart + 1}-$pageEnd of ${_waterRequests.length})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: safePage + 1 < pageCount
                    ? () => setState(() => _requestPage = safePage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const Center(
            child: Text(
              'Newest requests first',
              style: TextStyle(color: AppColors.mutedText, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Audit Trail Section
  // -------------------------------------------------------------------------
  Widget _buildAuditTrailSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "System Audit Trail",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryText,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "${_auditLog.length} Events",
                style: const TextStyle(
                  color: AppColors.primaryDarkGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (_auditLog.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 48,
                  color: AppColors.mutedText,
                ),
                SizedBox(height: 12),
                Text(
                  "No audit events recorded yet",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                children: _auditLog.take(20).map<Widget>((entry) {
                  final action = entry['action'] ?? '';
                  IconData icon;
                  Color iconColor;

                  switch (action) {
                    case 'USER_LOGIN':
                      icon = Icons.login_rounded;
                      iconColor = AppColors.primaryGreen;
                      break;
                    case 'USER_CREATED':
                      icon = Icons.person_add_rounded;
                      iconColor = AppColors.teal;
                      break;
                    case 'WATER_REQUEST':
                      icon = Icons.water_drop_rounded;
                      iconColor = AppColors.warning;
                      break;
                    case 'REQUEST_APPROVED':
                      icon = Icons.check_circle_rounded;
                      iconColor = AppColors.primaryGreen;
                      break;
                    case 'REQUEST_REJECTED':
                      icon = Icons.cancel_rounded;
                      iconColor = AppColors.danger;
                      break;
                    case 'FIELD_CREATED':
                      icon = Icons.grass_rounded;
                      iconColor = AppColors.brightGreen;
                      break;
                    case 'SYSTEM_INIT':
                      icon = Icons.power_settings_new_rounded;
                      iconColor = AppColors.primaryDarkGreen;
                      break;
                    default:
                      icon = Icons.info_outline_rounded;
                      iconColor = AppColors.secondaryText;
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.border, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: iconColor, size: 18),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${entry['details'] ?? ''}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.primaryText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "by ${entry['user'] ?? 'system'} • ${entry['timestamp'] ?? ''}",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.mutedText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            action.replaceAll('_', ' '),
                            style: TextStyle(
                              color: iconColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}

class _MetricStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String badgeText;
  final Color badgeColor;
  final String subtitle;
  final Color iconColor;

  const _MetricStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.badgeText,
    required this.badgeColor,
    required this.subtitle,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AppColors.mutedText),
          ),
        ],
      ),
    );
  }
}
