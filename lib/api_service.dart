import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

class ApiService {
  static Future<Map<String, dynamic>?> getIrrigationPrediction({
    required double reservoirWaterLevel,
    required double historicalRainfall,
    required List<Map<String, dynamic>> fields,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.predictIrrigationUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'reservoir_water_level_ft': reservoirWaterLevel,
          'historical_rainfall_mm': historicalRainfall,
          'fields': fields,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Server Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Network Error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getRealtimeReservoirData(
      {String reservoir = 'Nachchaduwa'}) async {
    try {
      final uri = Uri.parse(
          '${AppConfig.realtimeReservoirDataUrl}?reservoir=$reservoir');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Error fetching realtime reservoir data: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getWaterReleasePrediction({
    required String reservoir,
    Map<String, dynamic>? customOverrides,
  }) async {
    try {
      final bodyData = {'reservoir': reservoir, ...?customOverrides};
      final response = await http.post(
        Uri.parse(AppConfig.predictReleaseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bodyData),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Server Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Network Error predicting water release: $e');
    }
    return null;
  }
}
