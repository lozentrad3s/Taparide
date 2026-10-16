import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import 'router.dart';
import 'theme.dart';

class TapARideApp extends StatefulWidget {
  const TapARideApp({super.key, required this.state});
  final AppState state;

  @override
  State<TapARideApp> createState() => _TapARideAppState();
}

class _TapARideAppState extends State<TapARideApp> {
  late final GoRouter _router = buildRouter(widget.state);
  late final ThemeData _theme = buildAppTheme();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: widget.state,
      child: MaterialApp.router(
        title: 'Tap A Ride · Abuja Smart Mobility',
        debugShowCheckedModeBanner: false,
        theme: _theme,
        routerConfig: _router,
      ),
    );
  }
}
