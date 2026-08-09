import 'dart:convert';
import 'package:http/http.dart' as http;

class Weather {
  final double temperature;
  final String description;
  final String icon;
  final int humidity;
  final double windSpeed;

  Weather({
    required this.temperature,
    required this.description,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
  });

  factory Weather.fromOpenWeather(Map<String, dynamic> json) {
    final main = json['main'] ?? {};
    final weatherList = json['weather'] as List<dynamic>? ?? [];
    final wind = json['wind'] ?? {};

    return Weather(
      temperature: (main['temp'] as num?)?.toDouble() ?? 0.0,
      description: weatherList.isNotEmpty ? (weatherList[0]['description'] ?? '') : '',
      icon: weatherList.isNotEmpty ? (weatherList[0]['icon'] ?? '') : '',
      humidity: (main['humidity'] as num?)?.toInt() ?? 0,
      windSpeed: (wind['speed'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String iconUrl() => 'https://openweathermap.org/img/wn/$icon@2x.png';
}

class WeatherService {
  // API key configuration. Pass via --dart-define=OPENWEATHER_API_KEY=your_key or set here.
  static const String defaultApiKey = String.fromEnvironment('OPENWEATHER_API_KEY', defaultValue: '');

  static Future<Weather> fetchWeatherByCoords({
    required double lat,
    required double lon,
    String? apiKey,
  }) async {
    final key = apiKey ?? defaultApiKey;
    final url = Uri.parse('https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&units=metric&appid=$key');

    final resp = await http.get(url).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw Exception('Weather API error: ${resp.statusCode}');

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return Weather.fromOpenWeather(data);
  }
}
