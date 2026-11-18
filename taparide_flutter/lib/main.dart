import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/app_mode.dart';
import 'core/app_state.dart';
import 'core/backend/backend.dart';
import 'core/backend/demo_backend.dart';
import 'core/backend/supabase_backend.dart';
import 'core/error_reporting.dart';
import 'core/reminders.dart';
import 'shared/route_map.dart';

/// Pass `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` to use a
/// live Supabase project. Without them the app runs on on-device demo data.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorReporting.install(app: AppMode.current.name);
  final Backend backend = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty
      ? await SupabaseBackend.create(url: _supabaseUrl, anonKey: _supabaseAnonKey)
      : await DemoBackend.create();
  final reminders = ReminderService(await SharedPreferences.getInstance());
  final state = AppState(backend, reminders: reminders);
  await state.init();
  runApp(TapARideApp(state: state));
  // Credit whichever provider the server is using for map tiles.
  state.api.config().then((c) {
    state.setServices(c);
    MapTiles.attribution.value = switch (c['tiles']) {
      'maptiler' => '© MapTiler · © OpenStreetMap contributors',
      'carto' => '© OpenStreetMap contributors · © CARTO',
      _ => '© OpenStreetMap contributors',
    };
  });
}
