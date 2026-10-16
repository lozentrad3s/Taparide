import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Browser notifications for ride reminders (shown while the app is open in a tab).
Future<bool> requestNotificationPermission() async {
  try {
    if (web.Notification.permission == 'granted') return true;
    if (web.Notification.permission == 'denied') return false;
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart == 'granted';
  } catch (_) {
    return false;
  }
}

void showSystemNotification(String title, String body) {
  try {
    if (web.Notification.permission == 'granted') {
      web.Notification(title, web.NotificationOptions(body: body, icon: 'icons/Icon-192.png', tag: title));
    }
  } catch (_) {
    // Some browsers (iOS Safari outside a home-screen app) have no Notification API.
  }
}
