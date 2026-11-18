import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// Sends uncaught app errors to our server (`/api/client-error`), which forwards them to Sentry
/// when SENTRY_DSN is set there. No personal data is sent; at most 10 reports per session.
abstract final class ErrorReporting {
  static int _sent = 0;
  static final _seen = <String>{};

  static void install({required String app}) {
    if (kDebugMode) return;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack, app: app);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, app: app);
      return false;
    };
  }

  static void report(Object error, StackTrace? stack, {required String app}) {
    final message = error.toString();
    if (_sent >= 10 || !_seen.add(message)) return;
    _sent++;
    unawaited(http
        .post(
          Uri.parse('${apiBase()}/api/client-error'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'app': app,
            'message': message.length > 500 ? message.substring(0, 500) : message,
            'stack': stack?.toString().split('\n').take(20).join('\n'),
            'route': Uri.base.fragment.split('?').first,
          }),
        )
        .timeout(const Duration(seconds: 5))
        .then((_) {}, onError: (_) {}));
  }
}
