import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'app_theme.dart';
import 'auth_service.dart';
import 'field_creation_screen.dart';
import 'login_widgets.dart';
import 'main.dart';



class DashboardScreen extends StatefulWidget {
  final String farmerName;
  final String farmerEmail;
  final int farmerId;

  const DashboardScreen({
    super.key,
    required this.farmerName,
    required this.farmerEmail,
    required this.farmerId,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final String baseUrl = AppConfig.apiBaseUrl;

  List<dynamic> fields = [];
  List<dynamic> requests = [];
  bool isLoading = true;
  String _selectedNavItem = 'Dashboard';

  // Profile & Settings Controllers
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _zoneController;
  late TextEditingController _sizeController;
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;

  String _waterUnit = 'Liters (L)';
  String _moistureThreshold = '60%';
  bool _enableMoistureAlerts = true;
  bool _enableWeatherAlerts = true;
  bool _isSavingSettings = false;
  late String _currentFarmerName;

  // Telemetry real-time state variables
  Timer? _sensorTimer;
  bool _sensorFetchInProgress = false;
  num? liveMoisture;
  double? liveTemperature;
  int? sensorZoneNo;
  String sensorStatus = "No sensor data available";
  bool sensorConnected = false;

  Future<void> fetchSensorData() async {
    if (_sensorFetchInProgress) return;
    final token = AuthService.instance.sessionToken;
    if (token == null) {
      if (mounted) {
        setState(() {
        sensorConnected = false;
        sensorStatus = "Backend login required for ESP32 data";
        });
      }
      return;
    }
    _sensorFetchInProgress = true;
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/api/user/sensor-data"),
        headers: {"Authorization": "Bearer $token"},
      ).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (!mounted) return;
        setState(() {
          liveMoisture = data['moisture'] is num ? data['moisture'] as num : null;
          liveTemperature = data['temperature'] is num
              ? (data['temperature'] as num).toDouble() : null;
          sensorZoneNo = data['zoneNo'] is num ? (data['zoneNo'] as num).toInt() : null;
          sensorConnected = data['deviceStatus'] == 'ONLINE';
          sensorStatus = data['status'] == 'no_device'
              ? 'No ESP32 registered for this user'
              : sensorConnected ? 'ESP32 Online' : 'ESP32 Offline';
        });
      } else if (mounted) {
        setState(() {
          sensorConnected = false;
          sensorStatus = res.statusCode == 503
              ? 'Sensor database unavailable' : 'ESP32 data unavailable';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
        sensorConnected = false;
        sensorStatus = 'Sensor backend unreachable';
        });
      }
    } finally {
      _sensorFetchInProgress = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _currentFarmerName = widget.farmerName;
    _nameController = TextEditingController(text: widget.farmerName);
    _emailController = TextEditingController(text: widget.farmerEmail);
    _zoneController = TextEditingController(text: "1");
    _sizeController = TextEditingController(text: "4.5");
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    loadData();
    fetchSensorData();
    _sensorTimer = Timer.periodic(const Duration(seconds: 1), (_) => fetchSensorData());
  }

  @override
  void dispose() {
    _sensorTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _zoneController.dispose();
    _sizeController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() {
      isLoading = true;
    });

    List<dynamic> remoteFields = [];
    List<dynamic> remoteReqs = [];
    try {
      final fieldsResponse =
          await http.get(Uri.parse("$baseUrl/fields/${widget.farmerId}")).timeout(const Duration(seconds: 3));
      final fieldsData = jsonDecode(fieldsResponse.body);
      remoteFields = fieldsData['fields'] ?? [];

      final requestsResponse =
          await http.get(Uri.parse("$baseUrl/my-requests/${widget.farmerId}")).timeout(const Duration(seconds: 3));
      final requestsData = jsonDecode(requestsResponse.body);
      remoteReqs = requestsData['requests'] ?? [];
    } catch (e) {
      // Backend unreachable or offline
    }

    // Merge remote fields and local AuthService fields cleanly
    final localFields = AuthService.instance.getFarmerFields(widget.farmerId);
    final fieldMap = <int, dynamic>{};

    for (var f in localFields) {
      final fid = int.tryParse("${f['FieldID']}");
      if (fid != null) {
        fieldMap[fid] = f;
      }
    }
    for (var f in remoteFields) {
      final fid = int.tryParse("${f['FieldID']}");
      if (fid != null) {
        fieldMap[fid] = f;
      }
    }

    // Merge shared AuthService requests so real-time approvals/rejections from Admin are immediately shown to Farmer
    final localReqs = AuthService.instance.getFarmerRequests(widget.farmerId).map((r) => r.toJson()).toList();
    final combinedMap = <int, dynamic>{};
    for (var r in localReqs) {
      final rid = int.tryParse("${r['RequestID']}");
      if (rid != null) {
        combinedMap[rid] = r;
      }
    }
    for (var r in remoteReqs) {
      final rid = int.tryParse("${r['RequestID']}");
      if (rid != null) {
        combinedMap[rid] = r;
      }
    }

    if (mounted) {
      setState(() {
        fields = fieldMap.values.toList();
        requests = combinedMap.values.toList();
        isLoading = false;
        if (fields.isNotEmpty) {
          final firstField = fields.first;
          _zoneController.text = "${firstField['ZoneNo'] ?? ''}";
          _sizeController.text = "${firstField['Size'] ?? ''}";
        }
      });
    }
  }

  Future<void> requestWater(int fieldId) async {
    // Find zone name
    String zoneName = "Zone (Field #$fieldId)";
    for (var f in fields) {
      final fid = int.tryParse("${f['FieldID']}");
      if (fid == fieldId) {
        zoneName = "Zone ${f['ZoneNo']} (Field #$fieldId)";
        break;
      }
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/request-water"),
        headers: {
          "Content-Type": "application/json",
          if (AuthService.instance.sessionToken != null)
            "Authorization": "Bearer ${AuthService.instance.sessionToken}",
        },
        body: jsonEncode({
          "farmer_id": widget.farmerId,
          "field_id": fieldId,
        }),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 201) {
        _showMessage("Water request submitted successfully!", AppColors.primaryGreen);
        loadData();
      } else {
        _showMessage("Water request rejected by server (${response.statusCode})", Colors.redAccent);
      }
    } catch (e) {
      // Network error or timeout, fallback to local registration
      AuthService.instance.addWaterRequest(
        farmerId: widget.farmerId,
        fieldId: fieldId,
        zoneName: zoneName,
        farmerName: _currentFarmerName,
      );
      _showMessage("Water request saved locally; backend sync is pending", Colors.orangeAccent);
    }

    loadData();
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

  Future<void> _saveProfileSettings() async {
    setState(() {
      _isSavingSettings = true;
    });

    final currentPw = _currentPasswordController.text.trim();
    final newPw = _newPasswordController.text.trim();

    if (currentPw.isNotEmpty || newPw.isNotEmpty) {
      if (currentPw.isEmpty || newPw.isEmpty) {
        setState(() => _isSavingSettings = false);
        _showMessage("Please enter both current and new password to change password", Colors.orangeAccent);
        return;
      }

      // Update password locally in AuthService
      final localSuccess = AuthService.instance.changePassword(
        userId: widget.farmerId,
        userEmail: widget.farmerEmail,
        oldPassword: currentPw,
        newPassword: newPw,
      );

      // Update password on backend API
      bool remoteSuccess = false;
      try {
        final resp = await http.post(
          Uri.parse("$baseUrl/change-password"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "username": widget.farmerEmail.isNotEmpty ? widget.farmerEmail : _currentFarmerName,
            "old_password": currentPw,
            "new_password": newPw,
          }),
        ).timeout(const Duration(seconds: 3));

        if (resp.statusCode == 200) {
          remoteSuccess = true;
        }
      } catch (_) {}

      if (!localSuccess && !remoteSuccess) {
        setState(() => _isSavingSettings = false);
        _showMessage("Current password is incorrect!", Colors.redAccent);
        return;
      }

      _currentPasswordController.clear();
      _newPasswordController.clear();
    }

    final newName = _nameController.text.trim();
    if (newName.isNotEmpty) {
      setState(() {
        _currentFarmerName = newName;
      });
    }

    final zoneVal = int.tryParse(_zoneController.text.trim());
    final sizeVal = double.tryParse(_sizeController.text.trim());
    if (fields.isNotEmpty && zoneVal != null && sizeVal != null) {
      final firstField = fields.first;
      firstField['ZoneNo'] = zoneVal;
      firstField['Size'] = sizeVal;

      try {
        final localFields = AuthService.instance.getFarmerFields(widget.farmerId);
        for (var lf in localFields) {
          if (lf['FieldID'] == firstField['FieldID']) {
            lf['ZoneNo'] = zoneVal;
            lf['Size'] = sizeVal;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isSavingSettings = false;
      });
      _showMessage("Profile and settings saved successfully!", AppColors.primaryGreen);
    }
  }

  void _showFieldPicker() {
    if (fields.isEmpty) {
      _showMessage("Please register a field first", AppColors.warning);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.water_drop_rounded, color: AppColors.primaryDarkGreen, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Select Field for Irrigation",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
                      ),
                      Text("Request automated water allocation", style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: fields.map<Widget>((field) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppColors.inputBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.eco_rounded, color: AppColors.primaryGreen),
                        title: Text(
                          "Field #${field['FieldID']} - Zone ${field['ZoneNo']}",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText),
                        ),
                        subtitle: Text("Size: ${field['Size']} acres"),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.primaryGreen),
                        onTap: () {
                          Navigator.pop(context);
                          requestWater(field['FieldID']);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar() {
    final navItems = [
      {'icon': Icons.grid_view_rounded, 'title': 'Dashboard'},
      {'icon': Icons.settings_rounded, 'title': 'Settings'},
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
                  child: const Icon(Icons.water_drop_rounded, color: Colors.white, size: 24),
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
                      "AgTech AI Platform",
                      style: TextStyle(color: AppColors.lightGreen, fontSize: 11, fontWeight: FontWeight.w600),
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
                      setState(() {
                        _selectedNavItem = title;
                      });
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
                  child: Icon(Icons.person_rounded, color: AppColors.primaryDarkGreen, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentFarmerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const Text(
                        "FARMER ROLE",
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

  // Farmer Settings & Profile View
  Widget _buildSettingsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.settings_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Farmer Profile & Account Settings",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Manage your personal info, farm preferences, and security settings",
                        style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section 1: Profile Information Card
          Container(
            padding: const EdgeInsets.all(24),
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
                const Row(
                  children: [
                    Icon(Icons.person_outline_rounded, color: AppColors.primaryGreen, size: 22),
                    SizedBox(width: 10),
                    Text(
                      "Personal Profile Details",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  controller: _nameController,
                  labelText: "Full Name",
                  prefixIcon: Icons.person_rounded,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _emailController,
                  labelText: "Email Address",
                  prefixIcon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section 3: Password Security Card
          Container(
            padding: const EdgeInsets.all(24),
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
                const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: AppColors.primaryDarkGreen, size: 22),
                    SizedBox(width: 10),
                    Text(
                      "Account Security & Password",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  controller: _currentPasswordController,
                  labelText: "Current Password",
                  prefixIcon: Icons.lock_rounded,
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _newPasswordController,
                  labelText: "New Password",
                  prefixIcon: Icons.lock_reset_rounded,
                  obscureText: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Save Settings Button
          PrimaryButton(
            text: "SAVE PROFILE CHANGES",
            onPressed: _saveProfileSettings,
            isLoading: _isSavingSettings,
          ),
        ],
      ),
    );
  }

  // Dashboard Main Overview
  Widget _buildDashboardMainView() {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Banner Card matching global design system
            Container(
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
                          "SMART AGTECH • AI POWERED",
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
                    "Welcome, $_currentFarmerName 👋",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "AI-powered irrigation optimization helps you save water, improve crop yield, and automate zone scheduling.",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sensors_rounded, color: sensorConnected ? AppColors.brightGreen : Colors.orangeAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sensorStatus,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (sensorConnected ? AppColors.primaryGreen : Colors.orange).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: (sensorConnected ? AppColors.brightGreen : Colors.orangeAccent).withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            sensorConnected ? "ONLINE" : "OFFLINE",
                            style: TextStyle(color: sensorConnected ? AppColors.brightGreen : Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                ],
              ),
            ),

            const SizedBox(height: 28),

            // Metric Grid Cards (Soil Moisture & Temperature Telemetry)
            const Text(
              "System Metrics & Telemetry",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
            ),
            const SizedBox(height: 16),

            LayoutBuilder(
              builder: (context, constraints) {
                final colCount = constraints.maxWidth > 600 ? 2 : 1;
                return GridView.count(
                  crossAxisCount: colCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: constraints.maxWidth > 600 ? 2.2 : 1.8,
                  children: [
                    _MetricStatCard(
                      icon: Icons.opacity_rounded,
                      title: "Soil Moisture",
                      value: liveMoisture == null ? "--" : "$liveMoisture%",
                      badgeText: liveMoisture == null ? "No data" : liveMoisture! < 40 ? "Needs Water" : "Optimal",
                      badgeColor: liveMoisture != null && liveMoisture! < 40 ? AppColors.warning : AppColors.primaryGreen,
                      subtitle: "Moisture Index",
                      iconColor: AppColors.primaryGreen,
                    ),
                    _MetricStatCard(
                      icon: Icons.thermostat_rounded,
                      title: "Temperature",
                      value: liveTemperature == null ? "--" : "${liveTemperature!.toStringAsFixed(1)}°C",
                      badgeText: liveTemperature == null ? "No data" : liveTemperature! > 35 ? "High" : "Normal",
                      badgeColor: liveTemperature != null && liveTemperature! > 35 ? AppColors.danger : AppColors.warning,
                      subtitle: "Ambient Temp",
                      iconColor: AppColors.warning,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),

            // Quick Action Buttons


            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FieldCreationScreen(farmerId: widget.farmerId),
                        ),
                      );
                      loadData();
                    },
                    icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 20),
                    label: const Text("Add New Field", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showFieldPicker,
                    icon: const Icon(Icons.water_drop_outlined, color: Colors.white, size: 20),
                    label: const Text("Request Water", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Registered Fields Table Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Registered Fields & Soil Condition",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${fields.length} Fields",
                    style: const TextStyle(color: AppColors.primaryDarkGreen, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Data Table Container
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
                      DataColumn(label: Text("Field ID", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                      DataColumn(label: Text("Zone No", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                      DataColumn(label: Text("Size", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                      DataColumn(label: Text("Moisture", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                      DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                      DataColumn(label: Text("Action", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                    ],
                    rows: fields.map<DataRow>((f) {
                      final status = (f['Status'] ?? 'Optimal') as String;
                      final isOptimal = status == 'Optimal';
                      return DataRow(
                        cells: [
                          DataCell(Text("#${f['FieldID']}", style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text("Zone ${f['ZoneNo']}")),
                          DataCell(Text("${f['Size']} acres")),
                          DataCell(Text(sensorZoneNo == f['ZoneNo'] && liveMoisture != null
                              ? "$liveMoisture%" : "${f['Moisture'] ?? '--'}")),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isOptimal ? AppColors.lightGreen : Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: isOptimal ? AppColors.primaryDarkGreen : Colors.amber.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.water_drop_rounded, color: AppColors.primaryGreen, size: 20),
                              tooltip: "Request Water",
                              onPressed: () => requestWater(f['FieldID']),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Recent Water Requests Table Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Water Allocation Requests",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryText),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${requests.length} Requests",
                    style: const TextStyle(color: AppColors.primaryDarkGreen, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
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
                      DataColumn(label: Text("Zone / Field", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                      DataColumn(label: Text("Request Time", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                      DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText))),
                    ],
                    rows: requests.map<DataRow>((r) {
                      final status = (r['Status'] ?? 'Pending') as String;
                      final isApproved = status == 'Approved';
                      final isRejected = status == 'Rejected';

                      Color sColor = AppColors.primaryGreen;
                      Color sBg = AppColors.lightGreen;

                      if (isRejected) {
                        sColor = AppColors.danger;
                        sBg = Colors.red.withValues(alpha: 0.1);
                      } else if (!isApproved) {
                        sColor = AppColors.warning;
                        sBg = Colors.amber.withValues(alpha: 0.15);
                      }

                      final rawZone = "${r['ZoneName'] ?? ''}";
                      final fieldLabel = (!rawZone.contains("Field #") && r['FieldID'] != null)
                          ? "$rawZone (Field #${r['FieldID']})"
                          : rawZone;

                      return DataRow(
                        cells: [
                          DataCell(Text(fieldLabel, style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text("${r['RequestTime']}")),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: sBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: sColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: isDesktop ? null : Drawer(child: _buildSidebar()),
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
                child: const Icon(Icons.water_drop_rounded, color: AppColors.primaryDarkGreen, size: 20),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedNavItem == 'Settings' ? "Profile & Account Settings" : "Smart Irrigation Dashboard",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryText, fontSize: 16),
                  ),
                  Text(
                    _selectedNavItem == 'Settings' ? "Manage farmer details & preferences" : "AI-Powered Water Allocation & Telemetry",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.secondaryText, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),

        actions: [
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
          if (isDesktop) _buildSidebar(),
          Expanded(
            child: SafeArea(
              child: _selectedNavItem == 'Settings' ? _buildSettingsView() : _buildDashboardMainView(),
            ),
          ),
        ],
      ),
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
