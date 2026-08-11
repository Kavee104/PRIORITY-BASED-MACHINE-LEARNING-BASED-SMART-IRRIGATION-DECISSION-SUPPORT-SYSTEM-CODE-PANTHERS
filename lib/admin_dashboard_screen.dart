import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'app_theme.dart';
import 'auth_service.dart';
import 'main.dart';
import 'user_management_screen.dart';
import 'priority_schedule_screen.dart';
import 'water_release_prediction_card.dart';


class AdminDashboardScreen extends StatefulWidget {
  final String adminName;

  const AdminDashboardScreen({super.key, required this.adminName});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final String baseUrl = AppConfig.apiBaseUrl;
  static const String _adminKey = 'supersecretadminkey';

  String _selectedNavItem = 'Dashboard';
  bool _isLoading = true;

  // Stats from API
  Map<String, dynamic> _stats = {};

  // Water requests from API
  List<dynamic> _waterRequests = [];

  // Audit log from API
  List<dynamic> _auditLog = [];

  // Users from API
  List<dynamic> _apiUsers = [];

  // Action in progress tracking
  int? _actionInProgressId;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    await Future.wait([
      _fetchWaterRequests(),
      _fetchAuditLog(),
      _fetchUsers(),
    ]);

    await _fetchStats();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchStats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/stats?admin_key=$_adminKey'),
      ).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) _stats = data['stats'] ?? {};
      }
    } catch (_) {}

    if (mounted) {
      final combinedUsers = _getCombinedUsers();
      final allRequests = _getCombinedRequests();
      final pendingCount = allRequests.where((r) => r['Status'] == 'Pending').length;
      final approvedCount = allRequests.where((r) => r['Status'] == 'Approved').length;
      final rejectedCount = allRequests.where((r) => r['Status'] == 'Rejected').length;

      final farmerCount = combinedUsers.where((u) => u['role'].toString().toLowerCase() == 'farmer').length;
      final officerCount = combinedUsers.where((u) => u['role'].toString().toLowerCase() == 'officer').length;
      final adminCount = combinedUsers.where((u) => u['role'].toString().toLowerCase() == 'admin').length;

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
    final localReqs = AuthService.instance.getWaterRequests().map((r) => r.toJson()).toList();
    final combinedMap = <int, dynamic>{};
    for (var r in _waterRequests) {
      if (r['RequestID'] != null) combinedMap[r['RequestID'] as int] = r;
    }
    for (var r in localReqs) {
      combinedMap[r['RequestID'] as int] = r;
    }
    return combinedMap.values.toList();
  }

  List<Map<String, dynamic>> _getCombinedUsers() {
    final userMap = <String, Map<String, dynamic>>{};

    // 1. Add local AuthService accounts
    final accounts = AuthService.instance.getAllAccounts();
    for (var a in accounts) {
      final key = a.username.trim().toLowerCase();
      userMap[key] = {
        'username': a.username,
        'email': a.email,
        'name': a.name,
        'role': a.roleString,
      };
    }

    // 2. Add remote API users
    for (var u in _apiUsers) {
      final uname = (u['username'] ?? u['email'] ?? '').toString().trim();
      if (uname.isNotEmpty) {
        final key = uname.toLowerCase();
        userMap[key] = {
          'username': uname,
          'email': u['email'] ?? userMap[key]?['email'] ?? '$key@example.com',
          'name': u['name'] ?? userMap[key]?['name'] ?? uname,
          'role': (u['role'] ?? userMap[key]?['role'] ?? 'farmer').toString(),
        };
      }
    }

    return userMap.values.toList();
  }

  Future<void> _fetchWaterRequests() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/water-requests?admin_key=$_adminKey'),
      ).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) _waterRequests = data['requests'] ?? [];
      }
    } catch (_) {
      if (mounted) _waterRequests = [];
    }

    if (mounted) {
      setState(() {
        _waterRequests = _getCombinedRequests();
      });
    }
  }

  Future<void> _fetchAuditLog() async {
    List<dynamic> remoteLog = [];
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/audit-log?admin_key=$_adminKey'),
      ).timeout(const Duration(seconds: 3));
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
      final response = await http.get(
        Uri.parse('$baseUrl/admin/users?admin_key=$_adminKey'),
      ).timeout(const Duration(seconds: 3));
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
      await http.post(
        Uri.parse('$baseUrl/admin/water-requests/$requestId/approve?admin_key=$_adminKey'),
      ).timeout(const Duration(seconds: 3));
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
      await http.post(
        Uri.parse('$baseUrl/admin/water-requests/$requestId/reject?admin_key=$_adminKey'),
      ).timeout(const Duration(seconds: 3));
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
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold))),
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
      {'icon': Icons.supervised_user_circle_rounded, 'title': 'User Management'},
    ];

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.primaryDarkGreen,
      ),
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
                  child: const Icon(Icons.shield_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Smart Irrigation",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "ADMIN CONTROL",
                      style: TextStyle(color: AppColors.lightGreen, fontSize: 10, fontWeight: FontWeight.bold),
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
                    color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: Icon(
                      item['icon'] as IconData,
                      color: isSelected ? Colors.white : Colors.white70,
                      size: 22,
                    ),
                    title: Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      if (title == 'Priority Schedule') {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const PriorityScheduleScreen()));
                      } else if (title == 'User Management') {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
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
                  child: Icon(Icons.admin_panel_settings_rounded, color: AppColors.primaryDarkGreen, size: 20),
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
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const Text(
                        "SYSTEM ADMIN",
                        style: TextStyle(color: AppColors.lightGreen, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 18),
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
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
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: isDesktop ? null : Drawer(child: _buildSidebar(context)),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
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
                child: const Icon(Icons.shield_rounded, color: AppColors.primaryDarkGreen, size: 20),
              ),
              const SizedBox(width: 10),
            ],
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Admin Control Center",
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText, fontSize: 18),
                ),
                Text(
                  "Real-time System Administration & Water Approval",
                  style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.secondaryText),
            tooltip: "Refresh Data",
            onPressed: _loadAllData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.secondaryText),
            tooltip: "Logout",
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(context),
          Expanded(
            child: SafeArea(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
                  : RefreshIndicator(
                      color: AppColors.primaryGreen,
                      onRefresh: _loadAllData,
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          _buildHeroBanner(),
                          const SizedBox(height: 28),
                          _buildMetricsSection(),
                          const SizedBox(height: 32),
                          const WaterReleasePredictionCard(),
                          const SizedBox(height: 32),
                          _buildWaterRequestsSection(),

                          const SizedBox(height: 32),
                          _buildUsersSection(),
                          const SizedBox(height: 32),
                          _buildAuditTrailSection(),
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
      padding: const EdgeInsets.all(28),
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
            'Real-time water request approvals, user management, and system audit trail.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
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
    final userSubtitle = "${farmerCnt == 1 ? '1 Farmer' : '$farmerCnt Farmers'}, ${adminCnt == 1 ? '1 Admin' : '$adminCnt Admins'}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "System Metrics (Live)",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final colCount = constraints.maxWidth > 900 ? 5 : (constraints.maxWidth > 600 ? 3 : 2);
            return GridView.count(
              crossAxisCount: colCount,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.3,
              children: [
                _MetricStatCard(
                  icon: Icons.people_rounded,
                  title: "Total Users",
                  value: "$totalUsers",
                  badgeText: "Live",
                  badgeColor: AppColors.primaryGreen,
                  subtitle: userSubtitle,
                  iconColor: AppColors.primaryDarkGreen,
                ),
                _MetricStatCard(
                  icon: Icons.pending_actions_rounded,
                  title: "Pending Requests",
                  value: "$pendingReqs",
                  badgeText: pendingReqs > 0 ? "Action Needed" : "Clear",
                  badgeColor: pendingReqs > 0 ? AppColors.warning : AppColors.primaryGreen,
                  subtitle: "Awaiting approval",
                  iconColor: AppColors.warning,
                ),
                _MetricStatCard(
                  icon: Icons.check_circle_rounded,
                  title: "Approved",
                  value: "$approvedReqs",
                  badgeText: "Done",
                  badgeColor: AppColors.primaryGreen,
                  subtitle: "Water allocated",
                  iconColor: AppColors.primaryGreen,
                ),
                _MetricStatCard(
                  icon: Icons.cancel_rounded,
                  title: "Rejected",
                  value: "$rejectedReqs",
                  badgeText: rejectedReqs > 0 ? "Declined" : "None",
                  badgeColor: rejectedReqs > 0 ? AppColors.danger : AppColors.primaryGreen,
                  subtitle: "Requests denied",
                  iconColor: AppColors.danger,
                ),
                _MetricStatCard(
                  icon: Icons.water_drop_rounded,
                  title: "Total Requests",
                  value: "$totalReqs",
                  badgeText: "All Time",
                  badgeColor: AppColors.teal,
                  subtitle: "Water allocation requests",
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
  Widget _buildWaterRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Farmer Water Requests",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "${_waterRequests.length} Requests",
                style: const TextStyle(color: AppColors.primaryDarkGreen, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
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
                Icon(Icons.water_drop_outlined, size: 48, color: AppColors.mutedText),
                SizedBox(height: 12),
                Text(
                  "No water requests yet",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.secondaryText),
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
                  headingRowColor: WidgetStateProperty.all(AppColors.inputBackground),
                  columns: const [
                    DataColumn(label: Text("Req #", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                    DataColumn(label: Text("Farmer", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                    DataColumn(label: Text("Zone / Field", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                    DataColumn(label: Text("Requested At", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                    DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                    DataColumn(label: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                  ],
                  rows: _waterRequests.map<DataRow>((r) {
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
                    final fieldLabel = (!rawZone.contains("Field #") && r['FieldID'] != null)
                        ? "$rawZone (Field #${r['FieldID']})"
                        : rawZone;

                    return DataRow(
                      cells: [
                        DataCell(Text("#$reqId", style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text("${r['farmer_name'] ?? 'Unknown'}")),
                        DataCell(Text(fieldLabel)),
                        DataCell(Text("${r['RequestTime'] ?? ''}")),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: sBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(color: sColor, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ),
                        DataCell(
                          isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                                )
                              : isPending
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen, size: 22),
                                          tooltip: "Approve",
                                          onPressed: () => _approveRequest(reqId),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 22),
                                          tooltip: "Reject",
                                          onPressed: () => _rejectRequest(reqId),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      isApproved ? "✅ Done" : "❌ Denied",
                                      style: TextStyle(
                                        color: isApproved ? AppColors.primaryGreen : AppColors.danger,
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
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Registered Users Section (from API)
  // -------------------------------------------------------------------------
  Widget _buildUsersSection() {
    final displayUsers = _getCombinedUsers();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Registered Platform Users",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${displayUsers.length} Users",
                    style: const TextStyle(color: AppColors.primaryDarkGreen, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                  },
                  icon: const Icon(Icons.person_add_rounded, size: 16),
                  label: const Text("Add User", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),

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
                headingRowColor: WidgetStateProperty.all(AppColors.inputBackground),
                columns: const [
                  DataColumn(label: Text("Username", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                  DataColumn(label: Text("Role", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                  DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                ],
                rows: displayUsers.map<DataRow>((user) {
                  final roleStr = (user['role'] ?? 'farmer').toString().toUpperCase();
                  return DataRow(
                    cells: [
                      DataCell(Text("${user['username']}", style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: roleStr == 'ADMIN'
                                ? Colors.purple.withValues(alpha: 0.12)
                                : roleStr == 'OFFICER'
                                    ? AppColors.teal.withValues(alpha: 0.12)
                                    : AppColors.lightGreen,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            roleStr,
                            style: TextStyle(
                              color: roleStr == 'ADMIN'
                                  ? Colors.purple
                                  : roleStr == 'OFFICER'
                                      ? AppColors.teal
                                      : AppColors.primaryDarkGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.lightGreen,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            "Active",
                            style: TextStyle(color: AppColors.primaryDarkGreen, fontSize: 11, fontWeight: FontWeight.bold),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "${_auditLog.length} Events",
                style: const TextStyle(color: AppColors.primaryDarkGreen, fontWeight: FontWeight.bold, fontSize: 12),
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
                Icon(Icons.history_rounded, size: 48, color: AppColors.mutedText),
                SizedBox(height: 12),
                Text(
                  "No audit events recorded yet",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.secondaryText),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
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
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.primaryText),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "by ${entry['user'] ?? 'system'} • ${entry['timestamp'] ?? ''}",
                                style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            action.replaceAll('_', ' '),
                            style: TextStyle(color: iconColor, fontSize: 9, fontWeight: FontWeight.bold),
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
      padding: const EdgeInsets.all(16),
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
                  style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.secondaryText, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
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
