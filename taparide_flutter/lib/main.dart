import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/app_state.dart';
import 'core/backend/backend.dart';
import 'core/backend/demo_backend.dart';
import 'core/backend/supabase_backend.dart';

/// Pass `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` to use a
/// live Supabase project. Without them the app runs on on-device demo data.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Backend backend = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty
      ? await SupabaseBackend.create(url: _supabaseUrl, anonKey: _supabaseAnonKey)
      : await DemoBackend.create();
  final state = AppState(backend);
  await state.init();
  runApp(TapARideApp(state: state));
}
