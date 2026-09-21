const double targetSoilMoisture = 85.0;
const double criticalSoilMoisture = 40.0;
const double referenceTemperature = 25.0;
const double criticalTemperature = 30.0;
const double maximumIrrigationIntervalDays = 10.0;

double _normalized(double value) => value.clamp(0.0, 1.0).toDouble();

/// Urgency = 100 * (0.5Si + 0.3Ti + 0.2Di).
double calculateUrgencyScore({
  required double soilMoisture,
  required double temperature,
  required double daysSinceLastIrrigation,
}) {
  final soilFactor = _normalized(
    (targetSoilMoisture - soilMoisture) /
        (targetSoilMoisture - criticalSoilMoisture),
  );
  final temperatureFactor = _normalized(
    (temperature - referenceTemperature) /
        (criticalTemperature - referenceTemperature),
  );
  final irrigationIntervalFactor = _normalized(
    daysSinceLastIrrigation / maximumIrrigationIntervalDays,
  );

  return 100.0 *
      ((0.5 * soilFactor) +
          (0.3 * temperatureFactor) +
          (0.2 * irrigationIntervalFactor));
}
