import 'dart:math';

const double _earthRadius = 6371000; // Radius of the earth in meters

double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  double dLat = _toRadians(lat2 - lat1);
  double dLon = _toRadians(lon2 - lon1);

  lat1 = _toRadians(lat1);
  lat2 = _toRadians(lat2);

  double a =
      pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return _earthRadius * c;
}

double _toRadians(double degrees) {
  return degrees * (pi / 180);
}
