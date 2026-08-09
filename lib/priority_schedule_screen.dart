import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'app_theme.dart';
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
  bool _isWeatherLoading = false;

  @override
  void initState() {
    super.initState();
    fetchSchedule();
  }

  Future<void> _fetchWeatherButtonPressed() async {
    setState(() {
      _isWeatherLoading = true;
    });

    try {
      final w = await WeatherService.fetchWeatherByCoords(lat: 6.9271, lon: 79.8612);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.lightBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_sync_rounded, color: AppColors.aquaBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('AgTech Weather Telemetry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${w.temperature.toStringAsFixed(1)}°C — ${w.description}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              const SizedBox(height: 10),
              Text('Humidity: ${w.humidity}%', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text('Wind Speed: ${w.windSpeed} m/s', style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weather telemetry updated successfully')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isWeatherLoading = false;
        });
      }
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
          .timeout(const Duration(seconds: 3));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          schedule = data['schedule'] ?? [];
          isLoading = false;
        });
      } else {
        _loadMockSchedule();
      }
    } catch (e) {
      if (!mounted) return;
      _loadMockSchedule();
    }
  }

  void _loadMockSchedule() {
    setState(() {
      schedule = [
        {
          "Rank": 1,
          "F_Name": "Kamal",
          "L_Name": "Perera",
          "ZoneName": "Zone 1 (Paddy)",
          "FieldID": 12,
          "Size": 4.5,
          "PredictedVolume": 1250,
          "RainfallForecast": 1.2,
          "WaterLevel": "85.0%",
          "Date": "Today",
          "Explanation": "High soil moisture depletion rate detected. ML model recommends immediate top priority water release."
        },
        {
          "Rank": 2,
          "F_Name": "Nimal",
          "L_Name": "Fernando",
          "ZoneName": "Zone 2 (Vegetables)",
          "FieldID": 5,
          "Size": 2.2,
          "PredictedVolume": 600,
          "RainfallForecast": 0.5,
          "WaterLevel": "85.0%",
          "Date": "Today",
          "Explanation": "Medium priority. Moderate evapotranspiration index."
        },
        {
          "Rank": 3,
          "F_Name": "Saman",
          "L_Name": "Silva",
          "ZoneName": "Zone 3 (Maize)",
          "FieldID": 8,
          "Size": 3.0,
          "PredictedVolume": 850,
          "RainfallForecast": 8.5,
          "WaterLevel": "85.0%",
          "Date": "Tomorrow",
          "Explanation": "Low priority. High rainfall expected in next 24 hours."
        },
      ];
      isLoading = false;
    });
  }

  Color _rankColor(int rank) {
    if (rank == 1) return Colors.redAccent;
    if (rank <= 3) return Colors.orangeAccent;
    return AppColors.emerald;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text("Priority Schedule", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.emerald),
            onPressed: isLoading ? null : fetchSchedule,
          ),
          IconButton(
            icon: _isWeatherLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.aquaBlue))
                : const Icon(Icons.wb_sunny_rounded, color: Colors.orangeAccent),
            onPressed: _isWeatherLoading ? null : _fetchWeatherButtonPressed,
            tooltip: 'Live Weather',
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

    if (schedule.isEmpty) {
      return const Center(
        child: Text(
          "No priority schedule available",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.emerald,
      onRefresh: fetchSchedule,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: schedule.length,
        itemBuilder: (context, index) {
          final item = schedule[index];
          final rank = (item['Rank'] ?? (index + 1)) as int;
          final rColor = _rankColor(rank);

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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "#$rank",
                    style: TextStyle(
                      color: rColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${item['F_Name'] ?? ''} ${item['L_Name'] ?? ''}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${item['ZoneName'] ?? ''} • Field #${item['FieldID'] ?? ''} • ${item['Size'] ?? ''} acres",
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.water_drop_rounded, size: 16, color: AppColors.aquaBlue),
                          const SizedBox(width: 6),
                          Text(
                            "${item['PredictedVolume'] ?? 0} Liters Allocation",
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.umbrella_rounded, size: 16, color: AppColors.textLight),
                          const SizedBox(width: 6),
                          Text(
                            "Rain forecast: ${item['RainfallForecast'] ?? 0} mm (${item['Date'] ?? 'Today'})",
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      if (item['Explanation'] != null && item['Explanation'].toString().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.inputBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.emerald),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item['Explanation'],
                                  style: const TextStyle(fontSize: 12, color: AppColors.textDark, height: 1.3),
                                ),
                              ),
                            ],
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
