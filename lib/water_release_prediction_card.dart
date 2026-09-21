import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_theme.dart';

class WaterReleasePredictionCard extends StatefulWidget {
  const WaterReleasePredictionCard({super.key});

  @override
  State<WaterReleasePredictionCard> createState() =>
      _WaterReleasePredictionCardState();
}

class _WaterReleasePredictionCardState
    extends State<WaterReleasePredictionCard> {
  static const String _reservoirName = 'Mahakandarawa';

  bool _isLoading = false;
  Map<String, dynamic>? _predictionResult;

  @override
  void initState() {
    super.initState();
    _fetchPrediction();
  }

  Future<void> _fetchPrediction() async {
    setState(() {
      _isLoading = true;
    });

    final res = await ApiService.getWaterReleasePrediction(
      reservoir: _reservoirName,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res != null && res['status'] == 'success') {
          _predictionResult = res;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = _predictionResult?['input_features'] ?? {};
    final predictedVal =
        _predictionResult?['predicted_water_release']?.toStringAsFixed(2) ??
            '--';
    final dateStr = _predictionResult?['date'] ?? 'Live Today';
    final unitStr = _predictionResult?['unit'] ?? 'Acft/Day';

    final rawVal = _predictionResult?['predicted_water_release'];
    final double? releaseNum = rawVal is num ? rawVal.toDouble() : null;

    String releaseStatus = _predictionResult?['release_status'] ?? '';
    if (releaseStatus.isEmpty && releaseNum != null) {
      if (releaseNum < 80.0) {
        releaseStatus = 'Low';
      } else if (releaseNum <= 150.0) {
        releaseStatus = 'Medium';
      } else {
        releaseStatus = 'High';
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withValues(alpha: 0.12),
            blurRadius: 18.0,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: AppColors.teal.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.water_drop,
                    color: AppColors.teal,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ML Water Release Predictor',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                      Text(
                        'Mahakandarawa Reservoir • ArcGIS & Weather AI',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.teal,
                          ),
                        )
                      : const Icon(
                          Icons.refresh,
                          color: AppColors.teal,
                        ),
                  onPressed: _isLoading ? null : _fetchPrediction,
                  tooltip: 'Refresh Prediction',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey.withValues(alpha: 0.2)),
            const SizedBox(height: 12),

            // Fixed Target Reservoir Badge
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 20, color: AppColors.teal),
                const SizedBox(width: 8),
                const Text(
                  'Target Reservoir:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.teal.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.waves, size: 16, color: AppColors.teal),
                      SizedBox(width: 6),
                      Text(
                        'Mahakandarawa',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDarkGreen,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Main Prediction Result Display Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.teal.withValues(alpha: 0.12),
                    Colors.cyan.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.teal.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PREDICTED RELEASE AMOUNT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: AppColors.teal.withValues(alpha: 0.9),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.teal.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Update: $dateStr',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        predictedVal,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: AppColors.teal,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        unitStr,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  if (releaseStatus.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildStatusBadge(releaseStatus),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Live Input Features Matrix
            const Text(
              'ArcGIS & Weather Realtime Inputs:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Water Depth',
                    value:
                        '${features['Reservoir Water Level']?.toStringAsFixed(1) ?? '--'} ft',
                    icon: Icons.waves,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Capacity',
                    value:
                        '${features['Reservoir Capacity']?.toStringAsFixed(0) ?? '--'} Acft',
                    icon: Icons.pie_chart,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Rainfall',
                    value:
                        '${features['Rainfall (Nachchaduwa)']?.toStringAsFixed(1) ?? '0.0'} mm',
                    icon: Icons.cloudy_snowing,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.teal),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: AppColors.primaryText,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status.toUpperCase()) {
      case 'HIGH':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        icon = Icons.warning_amber_rounded;
        break;
      case 'MEDIUM':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
        icon = Icons.info_outline;
        break;
      case 'LOW':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        icon = Icons.check_circle_outline;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            '$status Release Demand',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
