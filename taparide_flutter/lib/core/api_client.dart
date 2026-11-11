import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'analytics.dart';
import 'backend/backend.dart';
import 'live_models.dart';
import 'partner_models.dart';

/// Where the Tap A Ride server API lives (Vercel functions + the FindMe AI proxy).
/// On the web it is the site itself; builds served elsewhere pass --dart-define=API_BASE=...
String apiBase() {
  const configured = String.fromEnvironment('API_BASE');
  if (configured.isNotEmpty) return configured;
  if (kIsWeb) {
    final origin = Uri.base.origin;
    // Local previews (flutter run / a static server) have no API; use production.
    if (origin.contains('localhost') || origin.contains('127.0.0.1')) return 'https://taparide.vercel.app';
    return origin;
  }
  return 'https://taparide.vercel.app';
}

class ToolCall {
  const ToolCall({required this.id, required this.name, required this.args});
  final String id;
  final String name;
  final Map<String, dynamic> args;
}

class AssistantStep {
  const AssistantStep({required this.history, required this.text, required this.toolCalls, required this.model});
  final List<dynamic> history;
  final String text;
  final List<ToolCall> toolCalls;
  final String model;
}

/// A driving/walking plan from FindMe AI's routing (OSRM/TomTom behind it).
class RoadPlan {
  const RoadPlan({required this.points, required this.distanceM, required this.durationS, required this.label, required this.steps, this.trafficDurationS});
  final List<LatLng> points;
  final int distanceM;
  final int durationS;
  final int? trafficDurationS;
  final String label;
  final List<String> steps;

  int get minutes => ((trafficDurationS ?? durationS) / 60).ceil();
  String get distanceText => distanceM >= 1000 ? '${(distanceM / 1000).toStringAsFixed(1)} km' : '$distanceM m';
}

class ApiClient {
  ApiClient(this._backend, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final Backend _backend;
  final http.Client _http;
  final _routeCache = <String, RoadPlan?>{};

  Uri _uri(String path) => Uri.parse('${apiBase()}$path');

  Future<Map<String, String>> _headers() async {
    final token = await _backend.accessToken();
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> _post(String path, Object body, {Duration timeout = const Duration(seconds: 60)}) async {
    final http.Response res;
    try {
      res = await _http.post(_uri(path), headers: await _headers(), body: jsonEncode(body)).timeout(timeout);
    } catch (_) {
      throw const BackendException(BackendErrorKind.network, 'Could not reach Tap A Ride. Check your connection and try again.');
    }
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {
      data = {};
    }
    if (res.statusCode >= 400) {
      final message = (data['error'] as String?) ?? 'The service is unavailable (${res.statusCode}).';
      throw BackendException(res.statusCode == 401 ? BackendErrorKind.auth : (res.statusCode == 429 ? BackendErrorKind.network : BackendErrorKind.unknown), message);
    }
    return data;
  }

  /// One step of the assistant's tool loop. [history] is opaque provider-native JSON.
  Future<AssistantStep> assistant({required String persona, required List<dynamic> history, String? text, Map<String, Object?>? context, List<Map<String, Object?>>? toolResults}) async {
    final data = await _post('/api/assistant', {
      'persona': persona,
      'history': history,
      'input': toolResults != null ? {'toolResults': toolResults} : {'text': text, 'context': context},
    });
    return AssistantStep(
      history: (data['history'] as List?) ?? const [],
      text: (data['text'] as String?) ?? '',
      toolCalls: [
        for (final c in (data['toolCalls'] as List? ?? const []))
          ToolCall(id: '${(c as Map)['id']}', name: '${c['name']}', args: Map<String, dynamic>.from((c['args'] as Map?) ?? const {})),
      ],
      model: (data['model'] as String?) ?? '',
    );
  }

  /// AI pre-check of partner documents against the typed details.
  Future<AiDocumentCheck> verifyDocuments(PartnerApplication draft, List<DocumentFile> documents) async {
    final data = await _post('/api/verify-documents', {
      'applicant': {
        'fullName': draft.fullName,
        'licenceNumber': draft.licenceNumber,
        'licenceExpiry': draft.toJson()['licence_expiry'],
        'plateNumber': draft.plateNumber,
        'chassisNumber': draft.chassisNumber,
        'vehicleMake': draft.vehicleMake,
        'vehicleModel': draft.vehicleModel,
        'vehicleYear': draft.vehicleYear,
        'vehicleColour': draft.vehicleColour,
      },
      'documents': [
        for (final d in documents)
          if (d.bytes != null) {'slot': d.slot.label, 'mimeType': d.mimeType, 'data': base64Encode(d.bytes!)},
      ],
    }, timeout: const Duration(seconds: 90));
    return AiDocumentCheck.fromJson(data);
  }

  /// Which services are live on the server (tiles provider, AI, backend). Never includes keys.
  Future<Map<String, dynamic>> config() async {
    try {
      final res = await _http.get(_uri('/api/config')).timeout(const Duration(seconds: 8));
      return res.statusCode == 200 ? Map<String, dynamic>.from(jsonDecode(res.body) as Map) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Starts a card or bank top-up and returns the payment page to send the rider to.
  Future<TopUpStart> startTopUp(int amount) async {
    final data = await _post('/api/pay?action=init', {'amount': amount}, timeout: const Duration(seconds: 30));
    return TopUpStart(url: '${data['url']}', reference: '${data['reference']}');
  }

  /// Asks the server to confirm a payment with the provider and credit the wallet (safe to repeat).
  Future<TopUpResult> verifyTopUp(String reference) async {
    final http.Response res;
    try {
      res = await _http.get(_uri('/api/pay').replace(queryParameters: {'action': 'verify', 'reference': reference}), headers: await _headers()).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const BackendException(BackendErrorKind.network, 'Could not reach Tap A Ride. Check your connection and try again.');
    }
    final data = Map<String, dynamic>.from(jsonDecode(res.body.isEmpty ? '{}' : res.body) as Map);
    if (res.statusCode >= 400) throw BackendException(BackendErrorKind.unknown, (data['error'] as String?) ?? 'The payment could not be checked (${res.statusCode}).');
    return TopUpResult(
      status: TopUpStatus.values.where((s) => s.name == data['status']).firstOrNull ?? TopUpStatus.pending,
      amount: (data['amount'] as num?)?.toInt() ?? 0,
    );
  }

  final _geoCache = <String, List<({String name, LatLng point})>>{};

  /// Place search inside the FCT (CARTO, with an OpenStreetMap fallback). Empty when nothing matches.
  Future<List<({String name, LatLng point})>> geocode(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    if (_geoCache.containsKey(q)) return _geoCache[q]!;
    try {
      final res = await _http.get(_uri('/api/geocode').replace(queryParameters: {'q': query.trim()}), headers: await _headers()).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final rows = ((jsonDecode(res.body) as Map)['results'] as List? ?? const []);
      return _geoCache[q] = [
        for (final r in rows.cast<Map>()) (name: '${r['name']}', point: LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble())),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The AI analyst's written reading of a partner's figures.
  Future<AiInsights> insights(Map<String, Object?> metrics) async => AiInsights.fromJson(await _post('/api/insights', {'metrics': metrics}, timeout: const Duration(seconds: 75)));

  /// Road geometry through every stop in order (one routing call per leg, cached). Null if any leg fails.
  Future<List<LatLng>?> roadPath(List<LatLng> stops) async {
    final legs = await Future.wait([for (var i = 0; i < stops.length - 1; i++) roadRoute(stops[i], stops[i + 1])]);
    if (legs.any((l) => l == null || l.points.length < 2)) return null;
    final path = cleanPath([for (final l in legs) ...l!.points]);
    return path.length < 2 ? null : path;
  }

  /// Road route between two points via the FindMe AI routing proxy. Null when unavailable.
  Future<RoadPlan?> roadRoute(LatLng from, LatLng to, {String mode = 'driving'}) async {
    final key = '${from.latitude.toStringAsFixed(4)},${from.longitude.toStringAsFixed(4)}>${to.latitude.toStringAsFixed(4)},${to.longitude.toStringAsFixed(4)}:$mode';
    if (_routeCache.containsKey(key)) return _routeCache[key];
    try {
      final res = await _http
          .post(
            _uri('/api/findme/route'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'from': {'lat': from.latitude, 'lng': from.longitude},
              'to': {'lat': to.latitude, 'lng': to.longitude},
              'mode': mode,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return _routeCache[key] = null;
      final route = ((jsonDecode(res.body) as Map)['plan'] as Map?)?['route'] as Map?;
      if (route == null) return _routeCache[key] = null;
      return _routeCache[key] = RoadPlan(
        points: decodePolyline('${route['geometry'] ?? ''}'),
        distanceM: (route['distanceM'] as num?)?.toInt() ?? 0,
        durationS: (route['durationS'] as num?)?.toInt() ?? 0,
        trafficDurationS: (route['trafficDurationS'] as num?)?.toInt(),
        label: '${route['label'] ?? ''}',
        steps: [for (final s in (route['steps'] as List? ?? const [])) '${(s as Map)['instruction'] ?? ''}'].where((s) => s.isNotEmpty).toList(),
      );
    } catch (_) {
      return null; // map still draws straight segments
    }
  }
}

/// Google encoded polyline (precision 5) -> points.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    for (var pass = 0; pass < 2; pass++) {
      var shift = 0, result = 0, b = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      // -(n + 1) rather than ~n: on the web ~ yields an unsigned 32-bit number.
      final delta = (result & 1) != 0 ? -((result >> 1) + 1) : (result >> 1);
      if (pass == 0) {
        lat += delta;
      } else {
        lng += delta;
      }
    }
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return cleanPath(points);
}

/// Drops repeated and invalid points so map lines never contain zero-length or NaN segments.
List<LatLng> cleanPath(Iterable<LatLng> points) {
  final out = <LatLng>[];
  for (final p in points) {
    if (!p.latitude.isFinite || !p.longitude.isFinite || p.latitude.abs() > 90 || p.longitude.abs() > 180) continue;
    if (out.isNotEmpty && (out.last.latitude - p.latitude).abs() < 1e-7 && (out.last.longitude - p.longitude).abs() < 1e-7) continue;
    out.add(p);
  }
  return out;
}
