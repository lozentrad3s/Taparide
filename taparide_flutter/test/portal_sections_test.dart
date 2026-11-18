// Pumps every portal section for every demo partner role at phone and desktop size
// and fails on any exception, layout overflow or page that never settles.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taparide_flutter/app/app.dart';
import 'package:taparide_flutter/app/app_mode.dart';
import 'package:taparide_flutter/core/app_state.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';
import 'package:taparide_flutter/features/portal/portal_shell.dart';

import 'test_support.dart';

const _phone = Size(390, 844);
const _desktop = Size(1440, 1000);

const _accounts = {
  'admin': 'admin@taparide.demo',
  'operator': 'ops@abujametro.demo',
  'fleet owner': 'fleet@greenfleet.demo',
  'EV operator': 'ev@naviride.demo',
  'FCTA': 'transport@fcta.demo',
  'event partner': 'events@taparide.demo',
  'private driver': 'grace@taparide.demo',
};

Future<AppState> _signedIn(WidgetTester tester, String email, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final (state, _) = (await tester.runAsync(freshState))!;
  await tester.runAsync(() => state.signIn(email: email, password: DemoSeed.password, portal: Portal.partner));
  await tester.pumpWidget(TapARideApp(state: state, mode: AppMode.dashboard));
  return state;
}

/// Lets futures that run outside the fake clock (the sign-ups list, traffic checks) finish.
/// A page that never settles (an endless spinner) is reported instead of hanging the test.
Future<void> _settle(WidgetTester tester, List<String> problems, String where) async {
  Future<void> settle() => tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 20));
  try {
    await settle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settle();
  } on FlutterError catch (e) {
    problems.add('$where: never settles (${e.message.split('\n').first})');
  }
}

List<PortalSection> sectionsFor(AppState state) {
  final user = state.user!;
  final privateDriver = user.role == UserRole.operator && state.providerById(user.providerId)?.kind == ProviderKind.privateDriver;
  return PortalSection.forRole(user.role, privateDriver: privateDriver);
}

void main() {
  for (final (sizeName, size) in [('phone', _phone), ('desktop', _desktop)]) {
    for (final MapEntry(key: role, value: email) in _accounts.entries) {
      testWidgets('every $role section renders cleanly on $sizeName', (tester) async {
        final problems = <String>[];
        final original = FlutterError.onError;
        var where = 'home';
        FlutterError.onError = (details) => problems.add('$where: ${details.exceptionAsString().split('\n').first}');
        try {
          final state = await _signedIn(tester, email, size);
          await _settle(tester, problems, where);
          final sections = sectionsFor(state);
          expect(sections, isNotEmpty);
          for (final s in sections) {
            where = s.path;
            GoRouter.of(tester.element(find.byType(Navigator).first)).go(s.path);
            await _settle(tester, problems, where);
            expect(find.byType(Scaffold), findsWidgets);
            // Scroll through the page so lazily built content is laid out too.
            final list = find.byType(ListView);
            if (list.evaluate().isNotEmpty) {
              for (var i = 0; i < 4; i++) {
                await tester.drag(list.first, const Offset(0, -1500), warnIfMissed: false);
                await _settle(tester, problems, '$where (scrolled)');
              }
            }
          }
        } finally {
          FlutterError.onError = original;
        }
        expect(problems, isEmpty, reason: problems.toSet().join('\n'));
      });
    }
  }
}
