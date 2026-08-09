import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

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
      _showMessage("Please enter zone number and field size");
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/create-field"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "farmer_id": widget.farmerId,
          "zone_no": int.parse(zoneText),
          "size": double.parse(size),
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        _showMessage("Field profile created successfully!");
        Navigator.pop(context);
      } else {
        _showMessage(data['error'] ?? "Failed to create field");
      }
    } catch (e) {
      _showMessage("Connection error: Could not reach server");
    }

    setState(() {
      isLoading = false;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Field Profile"),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Your Zone No",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: zoneController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "Enter your Zone No (1-28)",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              "Field Size (Acres)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: sizeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: "e.g. 1.5",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : createField,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "REGISTER FIELD",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
