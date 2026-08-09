import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'weather_service.dart';

class PriorityScheduleScreen extends StatefulWidget {
  const PriorityScheduleScreen({super.key});

  @override
  State<PriorityScheduleScreen> createState() => _PriorityScheduleScreenState();
}

class _PriorityScheduleScreenState extends State<PriorityScheduleScreen> {
  final String baseUrl = AppConfig.apiBaseUrl;

  bool isLoading = true;
  String? errorMessage;
  List<dynamic> schedule = [];
  // weather
  Weather? _weather;
  bool _isWeatherLoading = false;
  String? _weatherError;

  @override
  void initState() {
    super.initState();
    fetchSchedule();
  }

  Future<void> _fetchWeatherButtonPressed() async {
    setState(() {
      _isWeatherLoading = true;
      _weatherError = null;
    });

    try {
      // example coords (Colombo) — change if needed
      final w = await WeatherService.fetchWeatherByCoords(lat: 6.9271, lon: 79.8612);
      if (!mounted) return;
      setState(() {
        _weather = w;
      });

      // show dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Current Weather'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${w.temperature.toStringAsFixed(1)}°C — ${w.description}'),
              const SizedBox(height: 8),
              Text('Humidity: ${w.humidity}%'),
              Text('Wind: ${w.windSpeed} m/s'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weatherError = e.toString();
      });
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Weather Error'),
          content: Text(_weatherError ?? 'Unknown error'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isWeatherLoading = false;
      });
    }
  }

  Future<void> fetchSchedule() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse("$baseUrl/priority-schedule"))
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          schedule = data['schedule'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = "Failed to load priority schedule (${response.statusCode})";
          isLoading = false;
        });
      }
    } catch (e) {
      print("EXACT ERROR: $e");
      if (!mounted) return;
      setState(() {
        errorMessage = "Connection error: $e";
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
          IconButton(
            icon: _isWeatherLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud),
            onPressed: _isWeatherLoading ? null : _fetchWeatherButtonPressed,
            tooltip: 'Fetch weather',
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
          final rank = item['Rank'] ?? (index + 1);

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
                        "${item['F_Name'] ?? ''} ${item['L_Name'] ?? ''}",
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${item['ZoneName'] ?? ''} · Field #${item['FieldID'] ?? ''} · ${item['Size'] ?? ''} ac",
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.water_drop, size: 15, color: Colors.blue.shade400),
                          const SizedBox(width: 4),
                          Text(
                            "${item['PredictedVolume'] ?? 0} L predicted",
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
                            "Rain forecast: ${item['RainfallForecast'] ?? 0} mm (${item['Date'] ?? ''})",
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
                            "Reservoir level: ${item['WaterLevel'] ?? ''}",
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      if (item['Explanation'] != null &&
                          item['Explanation'].toString().isNotEmpty) ...[
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
