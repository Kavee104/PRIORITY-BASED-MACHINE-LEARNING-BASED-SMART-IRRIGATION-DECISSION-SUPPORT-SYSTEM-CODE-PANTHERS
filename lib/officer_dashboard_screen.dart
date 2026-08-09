// polling removed; manual-only reservoir control
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'irrigation_requests_screen.dart';
import 'priority_schedule_screen.dart';

class OfficerDashboardScreen extends StatefulWidget {
  final String officerName;

  const OfficerDashboardScreen({super.key, required this.officerName});

  @override
  State<OfficerDashboardScreen> createState() => _OfficerDashboardScreenState();
}

class _OfficerDashboardScreenState extends State<OfficerDashboardScreen> {
  final String baseUrl = AppConfig.apiBaseUrl;

  double? _reservoirLevel;
  String? _reservoirSource;
  String? _reservoirError;

  @override
  void initState() {
    super.initState();
  }
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _showSetReservoirDialog() async {
    final controller = TextEditingController(text: _reservoirLevel?.toStringAsFixed(1) ?? '');
    double? parsed;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Reservoir Level (%)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'Enter percent (0-100)'),
          onChanged: (v) {
            parsed = double.tryParse(v);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final value = double.tryParse(controller.text);
              if (value == null || value < 0 || value > 100) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid 0-100 value')));
                return;
              }
              Navigator.of(ctx).pop();
              await _setReservoirManual(value);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Future<void> _setReservoirManual(double value) async {
    setState(() {
      _reservoirError = null;
    });

    try {
      final candidates = [
        'reservoir-status',
        'reservoir',
        'reservoirs',
        'reservoir_status',
        'reservoirs/status',
        'reservoir-status/update',
        'reservoir/update'
      ];

      http.Response? successResp;
      String? successPath;
      for (final p in candidates) {
        try {
          final url = Uri.parse('$baseUrl/$p');
          final resp = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'level': value, 'source': 'manual'}),
          ).timeout(const Duration(seconds: 8));

          if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) {
            successResp = resp;
            successPath = p;
            break;
          }
          // continue trying if 404/405 etc.
        } catch (_) {
          // ignore and try next
        }
      }

      if (!mounted) return;
      if (successResp != null) {
        setState(() {
          _reservoirLevel = value;
          _reservoirSource = 'manual';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reservoir level updated (path: $successPath)')));
      } else {
        setState(() {
          _reservoirError = 'Update failed: endpoint not found or rejected request';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update failed: endpoint not found or rejected request')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reservoirError = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // manual-only mode: no fetch-from-backend helper needed

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Officer Dashboard'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blueGrey,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.badge, color: Colors.blueGrey, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome, Officer',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          widget.officerName.isNotEmpty ? widget.officerName : 'Officer',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            const Text(
              'Management Tools',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(height: 14),

            // Feature cards
            _DashboardCard(
              icon: Icons.water_drop,
              title: 'Irrigation Requests',
              subtitle: 'View and approve farmer requests',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const IrrigationRequestsScreen()),
                );
              },
            ),
            const SizedBox(height: 14),
            _DashboardCard(
              icon: Icons.priority_high,
              title: 'Priority Schedule',
              subtitle: 'View zone priority and scheduling',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PriorityScheduleScreen()),
                );
              },
            ),
            const SizedBox(height: 14),
            _ZoneReservoirCard(
              level: _reservoirLevel,
              source: _reservoirSource,
              error: _reservoirError,
              onEdit: _showSetReservoirDialog,
            ),
            const SizedBox(height: 14),
            _DashboardCard(
              icon: Icons.thermostat,
              title: 'Sensor Readings',
              subtitle: 'Temperature & soil moisture data',
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ??
            () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$title — coming soon")),
              );
            },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blueGrey.withOpacity(0.1),
                ),
                child: Icon(icon, color: Colors.blueGrey),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoneReservoirCard extends StatelessWidget {
  final double? level;
  final String? source;
  final String? error;
  final VoidCallback? onEdit;

  const _ZoneReservoirCard({this.level, this.source, this.error, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.teal.withOpacity(0.08),
                ),
                child: Icon(Icons.map, color: Colors.teal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Zone & Reservoir Status',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    if (error != null) ...[
                      Text('Error: $error', style: TextStyle(color: Colors.red.shade700)),
                    ] else ...[
                      Text(
                        level != null ? 'Reservoir level: ${level!.toStringAsFixed(1)}%' : 'Reservoir level: N/A',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text('Source: ${source ?? '-'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, color: Colors.grey),
                tooltip: 'Set level',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
