import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../shared/keyboard/keyboard.dart';
import 'app_mode.dart';
import 'router.dart';
import 'theme.dart';

class TapARideApp extends StatefulWidget {
  const TapARideApp({super.key, required this.state, this.mode});
  final AppState state;

  /// Overrides the build's APP_MODE (tests).
  final AppMode? mode;

  @override
  State<TapARideApp> createState() => _TapARideAppState();
}

class _TapARideAppState extends State<TapARideApp> {
  late final GoRouter _router = buildRouter(widget.state, mode: widget.mode);
  late final ThemeData _theme = buildAppTheme();

  @override
  void initState() {
    super.initState();
    // Phone browsers: tapping a text field after closing the keyboard must open it again.
    installKeyboardFix();
  }

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
        // The judges' demo (sample data on this device) says so on every screen.
        builder: (context, child) => widget.state.backend.isDemo ? _DemoFrame(child: child ?? const SizedBox.shrink()) : (child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// A slim strip above every demo screen: sample data, no real money, and a way to the live app.
class _DemoFrame extends StatelessWidget {
  const _DemoFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return Column(children: [
      Material(
        color: const Color(0xFF2B2205),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                const Icon(Icons.science_outlined, size: 16, color: Color(0xFFFFD36B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      narrow ? 'Demo · sample data, no real money' : 'Demo for judges · sample data on this device, no real money moves',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                // Out of the keyboard focus order: on the web, Flutter measures focusable widgets when the
                // tab gains focus, before this strip (outside the router) has been laid out.
                ExcludeFocus(
                  child: TextButton(
                    onPressed: () => launchUrl(Uri.parse('/app/'), webOnlyWindowName: '_blank'),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFFD36B),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(44, 32),
                        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                    child: const Text('Live app ↗'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
    ]);
  }
}
