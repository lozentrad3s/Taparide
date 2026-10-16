import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'models.dart';

/// Well-known Abuja places (real coordinates) for trip planning, EV pickups and the assistant.
const abujaPlaces = <String, (double, double)>{
  'Wuse 2': (9.0790, 7.4801),
  'Wuse': (9.0643, 7.4686),
  'Wuse Market': (9.0643, 7.4686),
  'Banex Junction': (9.0790, 7.4801),
  'Maitama': (9.0882, 7.4934),
  'Central Area': (9.0556, 7.4914),
  'Central Business District': (9.0556, 7.4914),
  'Federal Secretariat': (9.0505, 7.4995),
  'Garki': (9.0310, 7.4890),
  'Area 1': (9.0272, 7.4842),
  'Asokoro': (9.0420, 7.5250),
  'Jabi': (9.0705, 7.4250),
  'Jabi Lake Mall': (9.0748, 7.4236),
  'Utako': (9.0703, 7.4400),
  'Berger': (9.0679, 7.4560),
  'Life Camp': (9.0814, 7.4055),
  'Gwarinpa': (9.1099, 7.4083),
  'Kubwa': (9.1548, 7.3227),
  'Dutse': (9.1305, 7.3640),
  'Nyanya': (9.0213, 7.5616),
  'AYA': (9.0430, 7.5170),
  'Karu': (9.0170, 7.5480),
  'Lugbe': (8.9800, 7.3750),
  'Apo': (9.0040, 7.4930),
  'Lokogoma': (8.9920, 7.4590),
  'Idu': (9.0480, 7.3480),
  'Central Station': (9.0441, 7.4868),
  'Nnamdi Azikiwe Airport': (9.0068, 7.2632),
  'Airport': (9.0068, 7.2632),
  'National Assembly': (9.0597, 7.5154),
  'City Gate': (8.9881, 7.4029),
};

/// Places a rider can pick for an EV pickup or drop-off.
const evPlaceNames = ['Wuse 2', 'Maitama', 'Central Area', 'Garki', 'Asokoro', 'Jabi', 'Utako', 'Gwarinpa', 'Life Camp', 'Lugbe', 'Kubwa', 'Nnamdi Azikiwe Airport'];

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Finds a known place (or a route stop) by name, tolerating case and partial names.
({String name, LatLng point})? resolvePlace(String query, {List<TransitRoute> routes = const []}) {
  final q = _norm(query);
  if (q.isEmpty) return null;
  for (final e in abujaPlaces.entries) {
    if (_norm(e.key) == q) return (name: e.key, point: LatLng(e.value.$1, e.value.$2));
  }
  for (final r in routes) {
    for (final s in r.stops) {
      if (_norm(s.name) == q) return (name: s.name, point: LatLng(s.lat, s.lng));
    }
  }
  for (final e in abujaPlaces.entries) {
    final k = _norm(e.key);
    if (k.contains(q) || q.contains(k)) return (name: e.key, point: LatLng(e.value.$1, e.value.$2));
  }
  return null;
}

/// Road distance estimate between two named places (straight line × typical detour).
double roadKm(String a, String b) {
  final p = resolvePlace(a)?.point, q = resolvePlace(b)?.point;
  if (p == null || q == null) return 8;
  return straightKm(p, q) * 1.3;
}

double straightKm(LatLng p, LatLng q) {
  const r = 6371.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(q.latitude - p.latitude), dLng = rad(q.longitude - p.longitude);
  final h = sin(dLat / 2) * sin(dLat / 2) + cos(rad(p.latitude)) * cos(rad(q.latitude)) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * r * asin(sqrt(h));
}

/// Car fare: base plus distance, rounded to the nearest ₦50.
int carFare(Vehicle v, double km) => (((v.baseFare ?? 1200) + (v.perKmFare ?? 180) * km) / 50).round() * 50;

/// Minutes until a car can reach the pickup, from its current area.
int carEta(Vehicle v, String pickup) {
  final from = resolvePlace(v.area)?.name ?? 'Central Area';
  return max(3, (roadKm(from, pickup) * 2.2).round());
}
