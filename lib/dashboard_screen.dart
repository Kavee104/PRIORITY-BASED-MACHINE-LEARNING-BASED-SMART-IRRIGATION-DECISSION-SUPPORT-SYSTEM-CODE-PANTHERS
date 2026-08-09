import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'field_creation_screen.dart';
import 'main.dart';

class DashboardScreen extends StatefulWidget {
  final String farmerName;
  final int farmerId;

  const DashboardScreen({
    super.key,
    required this.farmerName,
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

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() {
      isLoading = true;
    });

    try {
      final fieldsResponse =
          await http.get(Uri.parse("$baseUrl/fields/${widget.farmerId}"));
      final fieldsData = jsonDecode(fieldsResponse.body);

      final requestsResponse =
          await http.get(Uri.parse("$baseUrl/my-requests/${widget.farmerId}"));
      final requestsData = jsonDecode(requestsResponse.body);

      setState(() {
        fields = fieldsData['fields'] ?? [];
        requests = requestsData['requests'] ?? [];
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      _showMessage("Could not load data. Check connection.");
    }
  }

  Future<void> requestWater(int fieldId) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/request-water"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "farmer_id": widget.farmerId,
          "field_id": fieldId,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        _showMessage("Water request submitted!");
        loadData();
      } else {
        _showMessage(data['error'] ?? "Failed to submit request");
      }
    } catch (e) {
      _showMessage("Connection error: Could not reach server");
    }
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

  void _showFieldPicker() {
    if (fields.isEmpty) {
      _showMessage("Please create a field profile first");
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          children: fields.map<Widget>((field) {
            return ListTile(
              leading: const Icon(Icons.grass, color: Colors.green),
              title: Text("Field #${field['FieldID']} - Zone ${field['ZoneNo']}"),
              subtitle: Text("Size: ${field['Size']} acres"),
              onTap: () {
                Navigator.pop(context);
                requestWater(field['FieldID']);
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Smart Irrigation"),
        backgroundColor: Colors.green,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
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
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadData,
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              const SizedBox(height: 10),
              Text(
                "Welcome, ${widget.farmerName}",
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: _InfoCard(
                      icon: Icons.thermostat,
                      label: "Temperature",
                      value: "30°C",
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _InfoCard(
                      icon: Icons.water_drop,
                      label: "Soil Moisture",
                      value: "65%",
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                // Add New Field button - always visible
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              FieldCreationScreen(farmerId: widget.farmerId),
                        ),
                      );
                      loadData();
                    },
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text(
                      "Add New Field",
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Request Water button - visible if at least 1 field exists
                if (fields.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showFieldPicker,
                      icon: const Icon(Icons.water_drop, color: Colors.white),
                      label: const Text(
                        "Request Water",
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 30),

                // My Fields section
                const Text(
                  "My Fields",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                if (fields.isEmpty)
                  const Text(
                    "No fields registered yet.",
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...fields.map((f) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.grass, color: Colors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Field #${f['FieldID']}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  "Zone ${f['ZoneNo']} • ${f['Size']} acres",
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 30),

                // My Requests section
                const Text(
                  "My Requests",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                if (requests.isEmpty)
                  const Text(
                    "No requests yet.",
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...requests.map((r) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${r['ZoneName']} (Field #${r['FieldID']})",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  r['RequestTime'],
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _statusColor(r['Status'])
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              r['Status'],
                              style: TextStyle(
                                color: _statusColor(r['Status']),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
