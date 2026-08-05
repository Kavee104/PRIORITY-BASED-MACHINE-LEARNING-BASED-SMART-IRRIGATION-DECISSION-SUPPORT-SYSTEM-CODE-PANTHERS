import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PriorityScheduleScreen extends StatefulWidget {
  const PriorityScheduleScreen({super.key});

  @override
  State<PriorityScheduleScreen> createState() => _PriorityScheduleScreenState();
}

class _PriorityScheduleScreenState extends State<PriorityScheduleScreen> {
 final String baseUrl = "http://10.95.149.28:5000";

  bool isLoading = true;
  String? errorMessage;
  List<dynamic> schedule = [];

  @override
  void initState() {
    super.initState();
    fetchSchedule();
  }

  Future<void> fetchSchedule() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse("$baseUrl/priority-schedule"));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          schedule = data['schedule'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = "Failed to load priority schedule";
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

  Color _rankColor(int rank) {
    if (rank == 1) return Colors.red;
    if (rank <= 3) return Colors.orange;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        title: const Text("Priority Schedule"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : fetchSchedule,
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
                onPressed: fetchSchedule,
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    if (schedule.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            "No priority schedule generated yet",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 15),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchSchedule,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: schedule.length,
        itemBuilder: (context, index) {
          final item = schedule[index];
          final rank = item['Rank'] as int;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _rankColor(rank).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "#$rank",
                    style: TextStyle(
                      color: _rankColor(rank),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${item['F_Name']} ${item['L_Name']}",
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${item['ZoneName']} · Field #${item['FieldID']} · ${item['Size']} ac",
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.water_drop, size: 15, color: Colors.blue.shade400),
                          const SizedBox(width: 4),
                          Text(
                            "${item['PredictedVolume']} L predicted",
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.cloud, size: 15, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            "Rain forecast: ${item['RainfallForecast']} mm (${item['Date']})",
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.water, size: 15, color: Colors.teal.shade400),
                          const SizedBox(width: 4),
                          Text(
                            "Reservoir level: ${item['WaterLevel']}",
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      if (item['Explanation'] != null && item['Explanation'].toString().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item['Explanation'],
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}