const double squareMetersPerAcre = 4047.0;

/// Calculates Vi in litres using:
/// max(0, (85 - Mi) + (Ti - 25) - (R * 0.1)) * Ai * 4047.
double calculateTargetWaterRequirementLiters({
  required double soilMoisture,
  required double temperature,
  required double previousDayRainfall,
  required double areaAcres,
}) {
  final adjustedDepth =
      (85.0 - soilMoisture) +
      (temperature - 25.0) -
      (previousDayRainfall * 0.1);
  final nonNegativeDepth = adjustedDepth < 0 ? 0.0 : adjustedDepth;
  final nonNegativeArea = areaAcres < 0 ? 0.0 : areaAcres;

  return nonNegativeDepth * nonNegativeArea * squareMetersPerAcre;
}
