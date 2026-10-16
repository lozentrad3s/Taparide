import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notify/notify_stub.dart' if (dart.library.js_interop) 'notify/notify_web.dart' as notify;

class TripReminder {
  const TripReminder({required this.id, required this.bookingId, required this.at, required this.title, required this.body});
  final String id;
  final String bookingId;
  final DateTime at;
  final String title;
  final String body;

  Map<String, Object?> toJson() => {'id': id, 'booking_id': bookingId, 'at': at.toIso8601String(), 'title': title, 'body': body};
  factory TripReminder.fromJson(Map<String, dynamic> json) =>
      TripReminder(id: '${json['id']}', bookingId: '${json['booking_id']}', at: DateTime.parse('${json['at']}'), title: '${json['title']}', body: '${json['body']}');
}

/// Ride reminders: saved on the device, fired as an in-app banner and (on the web) a browser notification.
class ReminderService extends ChangeNotifier {
  ReminderService(this._prefs, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _load();
  }

  static const _key = 'taparide_reminders_v1';
  final SharedPreferences? _prefs;
  final DateTime Function() _clock;
  final _timers = <String, Timer>{};
  List<TripReminder> _items = [];

  /// The most recent reminder that fired and has not been dismissed.
  TripReminder? active;

  List<TripReminder> get upcoming => [for (final r in _items) if (r.at.isAfter(_clock())) r]..sort((a, b) => a.at.compareTo(b.at));
  List<TripReminder> forBooking(String bookingId) => [for (final r in upcoming) if (r.bookingId == bookingId) r];

  void _load() {
    try {
      final raw = _prefs?.getString(_key);
      if (raw != null) _items = [for (final r in (jsonDecode(raw) as List)) TripReminder.fromJson(Map<String, dynamic>.from(r as Map))];
    } catch (_) {
      _items = [];
    }
    _items.removeWhere((r) => r.at.isBefore(_clock().subtract(const Duration(hours: 1))));
    for (final r in _items) {
      _arm(r);
    }
  }

  void _save() => _prefs?.setString(_key, jsonEncode([for (final r in _items) r.toJson()]));

  void _arm(TripReminder r) {
    _timers[r.id]?.cancel();
    final wait = r.at.difference(_clock());
    if (wait.isNegative) return;
    _timers[r.id] = Timer(wait, () => _fire(r));
  }

  void _fire(TripReminder r) {
    active = r;
    notify.showSystemNotification(r.title, r.body);
    notifyListeners();
  }

  Future<bool> requestPermission() => notify.requestNotificationPermission();

  void add(TripReminder r) {
    _items.removeWhere((x) => x.id == r.id);
    _items.add(r);
    _arm(r);
    _save();
    notifyListeners();
  }

  void cancelFor(String bookingId) {
    for (final r in _items.where((r) => r.bookingId == bookingId)) {
      _timers.remove(r.id)?.cancel();
    }
    _items.removeWhere((r) => r.bookingId == bookingId);
    _save();
    notifyListeners();
  }

  void dismiss() {
    active = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }
}
