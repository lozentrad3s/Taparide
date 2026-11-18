// Checks that the main dashboard controls do what they say.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taparide_flutter/app/app.dart';
import 'package:taparide_flutter/app/app_mode.dart';
import 'package:taparide_flutter/core/app_state.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';

import 'test_support.dart';

Future<AppState> _signedIn(WidgetTester tester, String email, {Size size = const Size(1440, 1000)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(loadAppFonts);
  final (state, _) = (await tester.runAsync(freshState))!;
  await tester.runAsync(() => state.signIn(email: email, password: DemoSeed.password, portal: Portal.partner));
  await tester.pumpWidget(TapARideApp(state: state, mode: AppMode.dashboard));
  await tester.pumpAndSettle();
  return state;
}

Future<void> _go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(path);
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pumpAndSettle();
}

/// Taps a widget after scrolling the page until it is on screen.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the FCTA verifies a pending vehicle from the verification queue', (tester) async {
    final state = await _signedIn(tester, 'transport@fcta.demo');
    await _go(tester, '/portal/verification');
    final pending = state.vehicles.where((v) => v.verification == Verification.pending).length;
    expect(pending, greaterThan(0));
    await _tap(tester, find.widgetWithText(FilledButton, 'Verify').first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(state.vehicles.where((v) => v.verification == Verification.pending).length, pending - 1);
  });

  testWidgets('demand view switches between estimated riders and app bookings', (tester) async {
    await _signedIn(tester, 'ops@abujametro.demo');
    await _go(tester, '/portal/insights');
    expect(find.text('Demand by corridor and hour'), findsWidgets);
    expect(find.textContaining('Busiest:'), findsOneWidget);
    await _tap(tester, find.text('App bookings').first);
    expect(find.textContaining('booked', findRichText: true), findsWidgets);
    expect(find.text('Booked'), findsOneWidget, reason: 'the totals column now counts app bookings');
  });

  testWidgets('admins can view insights as any organisation', (tester) async {
    await _signedIn(tester, 'admin@taparide.demo');
    await _go(tester, '/portal/insights');
    expect(find.textContaining('Whole platform'), findsWidgets);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capital Metro Rail Services (sample)').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Capital Metro Rail Services (sample) ·'), findsWidgets);
    expect(find.text('MR1'), findsWidgets, reason: 'the heatmap shows the rail corridors');
  });

  testWidgets('the website sign-ups page loads for admins', (tester) async {
    await _signedIn(tester, 'admin@taparide.demo');
    await _go(tester, '/portal/waitlist');
    expect(find.text('Website sign-ups'), findsWidgets);
    expect(find.text('Joined the waitlist'), findsOneWidget);
    expect(find.text('Tech Week boarding lists'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the register-vehicle quick action opens the form', (tester) async {
    await _signedIn(tester, 'ops@abujametro.demo');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Register vehicle'));
    await tester.pumpAndSettle();
    expect(find.text('Register a vehicle'), findsOneWidget);
  });

  testWidgets('on a phone, More lists the remaining sections and navigates', (tester) async {
    await _signedIn(tester, 'transport@fcta.demo', size: const Size(390, 844));
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('OVERSIGHT'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Audit log'), 200, scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audit log'));
    await tester.pumpAndSettle();
    expect(find.text('Every approval, suspension, fare change and role change, with who made it'), findsOneWidget);
  });
}
