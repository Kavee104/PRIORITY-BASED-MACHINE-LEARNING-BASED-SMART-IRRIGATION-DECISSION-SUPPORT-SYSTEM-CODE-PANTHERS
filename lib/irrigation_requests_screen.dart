import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'app_theme.dart';

class IrrigationRequestsScreen extends StatefulWidget {
  const IrrigationRequestsScreen({super.key});

  @override
  State<IrrigationRequestsScreen> createState() => _IrrigationRequestsScreenState();
}

class _IrrigationRequestsScreenState extends State<IrrigationRequestsScreen> {
  final String baseUrl = AppConfig.apiBaseUrl;

  bool isLoading = true;
  String? errorMessage;
  List<dynamic> requests = [];
  int? actionInProgressId;

  @override
  void initState() {
    super.initState();
    fetchRequests();
  }

  Future<void> fetchRequests() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse("$baseUrl/requests")).timeout(const Duration(seconds: 3));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          requests = data['requests'] ?? [];
          isLoading = false;
        });
      } else {
        _loadMockData();
      }
    } catch (e) {
      if (!mounted) return;
      _loadMockData();
    }
  }

  void _loadMockData() {
    setState(() {
      requests = [
        {
          "RequestID": 101,
          "F_Name": "Kamal",
          "L_Name": "Perera",
          "Status": "Pending",
          "ZoneName": "Zone 1 (Paddy)",
          "FieldID": 12,
          "Size": 4.5,
          "RequestTime": "10 mins ago"
        },
        {
          "RequestID": 102,
          "F_Name": "Saman",
          "L_Name": "Silva",
          "Status": "Approved",
          "ZoneName": "Zone 3 (Maize)",
          "FieldID": 8,
          "Size": 3.0,
          "RequestTime": "1 hour ago"
        },
        {
          "RequestID": 103,
          "F_Name": "Nimal",
          "L_Name": "Fernando",
          "Status": "Pending",
          "ZoneName": "Zone 2 (Vegetables)",
          "FieldID": 5,
          "Size": 2.2,
          "RequestTime": "2 hours ago"
        },
      ];
      isLoading = false;
    });
  }

  Future<void> respondToRequest(int requestId, String action) async {
    setState(() {
      actionInProgressId = requestId;
    });

    try {
      await http.post(
        Uri.parse("$baseUrl/requests/$requestId/$action"),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      final index = requests.indexWhere((r) => r['RequestID'] == requestId);
      if (index != -1) {
        requests[index]['Status'] = action == 'approve' ? 'Approved' : 'Rejected';
      }
      actionInProgressId = null;
    });

    _showMessage(action == 'approve' ? "Request approved" : "Request rejected", 
      action == 'approve' ? AppColors.emerald : Colors.redAccent);
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Approved':
        return AppColors.emerald;
      case 'Rejected':
        return Colors.redAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text("Irrigation Requests", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.emerald),
            onPressed: isLoading ? null : fetchRequests,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.emerald));
    }

    if (requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.water_drop_outlined, size: 56, color: AppColors.textLight),
            SizedBox(height: 12),
            Text(
              "No irrigation requests pending",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.emerald,
      onRefresh: fetchRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final req = requests[index];
          final requestId = req['RequestID'] as int;
          final status = (req['Status'] ?? 'Pending') as String;
          final isPending = status == 'Pending';
          final isBusy = actionInProgressId == requestId;
          final sColor = _statusColor(status);

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(20),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: sColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.person_rounded, color: sColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "${req['F_Name']} ${req['L_Name']}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: sColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.grass_rounded, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      "${req['ZoneName']} • Field #${req['FieldID']} • ${req['Size']} acres",
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 18, color: AppColors.textLight),
                    const SizedBox(width: 8),
                    Text(
                      "${req['RequestTime']}",
                      style: const TextStyle(color: AppColors.textLight, fontSize: 13),
                    ),
                  ],
                ),
                if (isPending) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isBusy ? null : () => respondToRequest(requestId, 'reject'),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: isBusy
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text("Decline"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isBusy ? null : () => respondToRequest(requestId, 'approve'),
                          icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                          label: isBusy
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text("Approve", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
