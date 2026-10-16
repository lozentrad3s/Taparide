import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// The rider's position, if they allow it. Never throws; null means "unknown".
Future<LatLng?> currentLocation({Duration timeout = const Duration(seconds: 8)}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium)).timeout(timeout);
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    return null;
  }
}

/// Abuja's city centre, used when the rider's location is unknown.
const abujaCentre = LatLng(9.0579, 7.4951);

/// Rough check that a point is in or near the FCT (so far-away browsers don't skew travel times).
bool inFct(LatLng p) => p.latitude > 8.4 && p.latitude < 9.6 && p.longitude > 6.7 && p.longitude < 7.9;
