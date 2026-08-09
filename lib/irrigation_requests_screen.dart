import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

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

  // Tracks which request id is currently being approved/rejected,
  // so only that row shows a spinner instead of blocking the whole screen.
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
      final response = await http.get(Uri.parse("$baseUrl/requests"));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          requests = data['requests'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = "Failed to load requests";
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = "Connection error: Could not reach server";
        isLoading = false;
      });
    }
  }

  Future<void> respondToRequest(int requestId, String action) async {
    setState(() {
      actionInProgressId = requestId;
    });

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/requests/$requestId/$action"),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        _showMessage(action == 'approve' ? "Request approved" : "Request rejected");
        await fetchRequests(); // refresh list so the status/buttons update
      } else {
        _showMessage("Action failed. Try again.");
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage("Connection error: Could not reach server");
    }

    if (!mounted) return;
    setState(() {
      actionInProgressId = null;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        title: const Text("Irrigation Requests"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : fetchRequests,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: fetchRequests,
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    if (requests.isEmpty) {
      return const Center(
        child: Text(
          "No irrigation requests yet",
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final req = requests[index];
          final requestId = req['RequestID'] as int;
          final status = req['Status'] ?? 'Pending';
          final isPending = status == 'Pending';
          final isBusy = actionInProgressId == requestId;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "${req['F_Name']} ${req['L_Name']}",
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.map, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      "${req['ZoneName']} · Field #${req['FieldID']} · ${req['Size']} ac",
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      "${req['RequestTime']}",
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ],
                ),
                if (isPending) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isBusy ? null : () => respondToRequest(requestId, 'reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          child: isBusy
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text("Reject"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isBusy ? null : () => respondToRequest(requestId, 'approve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          child: isBusy
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text("Approve", style: TextStyle(color: Colors.white)),
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
