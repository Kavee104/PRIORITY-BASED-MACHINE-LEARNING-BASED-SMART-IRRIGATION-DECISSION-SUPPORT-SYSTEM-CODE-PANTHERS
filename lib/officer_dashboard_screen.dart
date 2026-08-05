import 'package:flutter/material.dart';
import 'irrigation_requests_screen.dart';
import 'priority_schedule_screen.dart';

class OfficerDashboardScreen extends StatelessWidget {
  final String officerName;

  const OfficerDashboardScreen({super.key, required this.officerName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text("Officer Dashboard"),
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
                          "Welcome, Officer",
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          officerName.isNotEmpty ? officerName : "Officer",
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
              "Management Tools",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(height: 14),

            // Feature cards — placeholders for now, wired up next
            _DashboardCard(
              icon: Icons.water_drop,
              title: "Irrigation Requests",
              subtitle: "View and approve farmer requests",
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
              title: "Priority Schedule",
              subtitle: "View zone priority and scheduling",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PriorityScheduleScreen()),
                );
              },
            ),
            const SizedBox(height: 14),
            _DashboardCard(
              icon: Icons.map,
              title: "Zone & Reservoir Status",
              subtitle: "Monitor water levels across zones",
            ),
            const SizedBox(height: 14),
            _DashboardCard(
              icon: Icons.thermostat,
              title: "Sensor Readings",
              subtitle: "Temperature & soil moisture data",
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