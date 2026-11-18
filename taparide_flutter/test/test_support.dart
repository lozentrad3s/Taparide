import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taparide_flutter/app/app.dart';
import 'package:taparide_flutter/app/app_mode.dart';
import 'package:taparide_flutter/core/app_state.dart';
import 'package:taparide_flutter/core/backend/demo_backend.dart';
import 'package:taparide_flutter/shared/route_map.dart';
import 'package:taparide_flutter/shared/ticking.dart';

/// Fresh demo backend + app state with no artificial latency.
Future<(AppState, DemoBackend)> freshState() async {
  SharedPreferences.setMockInitialValues({});
  MapTiles.enabled = false;
  LiveTicking.enabled = false;
  final backend = await DemoBackend.create(latency: Duration.zero);
  final state = AppState(backend);
  await state.init();
  return (state, backend);
}

Future<AppState> pumpApp(WidgetTester tester, {Size size = const Size(390, 844), AppMode? mode}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(loadAppFonts);
  final (state, _) = await tester.runAsync(freshState) ?? (throw StateError('setup failed'));
  await tester.pumpWidget(TapARideApp(state: state, mode: mode));
  await tester.pumpAndSettle();
  return state;
}

/// Loads every font in the app's font manifest (Barlow, Fira Sans, Material icons)
/// so screenshots show real type instead of the test font.
Future<void> loadAppFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest) {
    final family = (entry as Map)['family'] as String;
    final loader = FontLoader(family.replaceFirst('packages/cupertino_icons/', ''));
    for (final font in (entry['fonts'] as List)) {
      loader.addFont(rootBundle.load((font as Map)['asset'] as String));
    }
    await loader.load();
  }
}
