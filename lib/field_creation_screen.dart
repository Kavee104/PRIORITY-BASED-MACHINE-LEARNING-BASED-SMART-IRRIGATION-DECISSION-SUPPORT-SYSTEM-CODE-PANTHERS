import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'app_theme.dart';
import 'auth_service.dart';

class FieldCreationScreen extends StatefulWidget {
  final int farmerId;

  const FieldCreationScreen({super.key, required this.farmerId});

  @override
  State<FieldCreationScreen> createState() => _FieldCreationScreenState();
}

class _FieldCreationScreenState extends State<FieldCreationScreen> {
  final TextEditingController zoneController = TextEditingController();
  final TextEditingController sizeController = TextEditingController();
  final String baseUrl = AppConfig.apiBaseUrl;

  bool isLoading = false;

  Future<void> createField() async {
    final zoneText = zoneController.text.trim();
    final size = sizeController.text.trim();

    if (zoneText.isEmpty || size.isEmpty) {
      _showMessage("Please enter zone number and field size", Colors.orangeAccent);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/fields/${widget.farmerId}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "zone_no": int.tryParse(zoneText) ?? 1,
          "size": double.tryParse(size) ?? 1.0,
          "crop_type": "General",
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        _showMessage("Field profile created successfully!", AppColors.emerald);
        Navigator.pop(context);
        return;
      }

      AuthService.instance.addFarmerField(
        farmerId: widget.farmerId,
        zoneNo: int.tryParse(zoneText) ?? 1,
        size: double.tryParse(size) ?? 1.0,
        cropType: "General",
      );

      if (!mounted) return;
      _showMessage("Field profile created!", AppColors.emerald);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AuthService.instance.addFarmerField(
        farmerId: widget.farmerId,
        zoneNo: int.tryParse(zoneText) ?? 1,
        size: double.tryParse(size) ?? 1.0,
        cropType: "General",
      );
      _showMessage("Field registered locally!", AppColors.emerald);
      Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showMessage(String message, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text("Register New Field", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.grass_rounded, color: AppColors.emerald, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Field Profile Details",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
                        ),
                        Text(
                          "Add zone parameters for automated water scheduling",
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              Text(
                "Zone Number",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: zoneController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: "Enter Zone No (e.g. 1 - 28)",
                  prefixIcon: Icon(Icons.map_rounded, color: AppColors.emerald),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                "Field Size (Acres)",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: sizeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: "e.g. 2.5",
                  prefixIcon: Icon(Icons.square_foot_rounded, color: AppColors.emerald),
                  suffixText: "Acres",
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : createField,
                  icon: isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, color: Colors.white),
                  label: Text(
                    isLoading ? "SAVING..." : "REGISTER FIELD",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
