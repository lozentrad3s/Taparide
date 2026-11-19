import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taparide_flutter/app/app.dart';
import 'package:taparide_flutter/app/app_mode.dart';
import 'package:taparide_flutter/core/backend/backend.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';
import 'package:taparide_flutter/features/common/redirect_pages.dart';
import 'package:taparide_flutter/features/onboarding/onboarding_page.dart';

import 'test_support.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first visit: three onboarding pages, then sign-up with Google or email (no Apple until we have a developer account)', (tester) async {
    await pumpApp(tester, mode: AppMode.rider);
    expect(find.text('Move more.\nWorry less.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Ride together,\npay less.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('I already have an account'), findsOneWidget);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your rider account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('Partner portal'), findsNothing, reason: 'the rider app has no partner sign-in');

    // The demo has no Google: it says so instead of failing silently.
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('works on the live app'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(OnboardingPage.seenKey), isTrue);
  });

  testWidgets('returning visitors skip the onboarding', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final (state, _) = (await tester.runAsync(freshState))!;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingPage.seenKey, true);
    await tester.pumpWidget(TapARideApp(state: state, mode: AppMode.rider));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('"Open my account" from the website signs out a different account and fills in the email', (tester) async {
    final state = await pumpApp(tester, mode: AppMode.rider);
    await tester.runAsync(() => state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger));
    await tester.pumpAndSettle();
    expect(find.textContaining(', Aisha'), findsOneWidget);

    await go(tester, '/register?email=new.rider@example.com&ref=ABC123');
    await tester.pumpAndSettle();
    expect(state.user, isNull, reason: 'the old demo session is closed');
    expect(find.text('Create your rider account'), findsOneWidget);
    expect(find.text('new.rider@example.com'), findsOneWidget);
  });

  testWidgets('the rider app sends dashboard links to the dashboard site, and back', (tester) async {
    await pumpApp(tester, mode: AppMode.rider);
    await go(tester, '/partner/apply?type=busOperator');
    final moved = tester.widget<ElsewherePage>(find.byType(ElsewherePage));
    expect(moved.toDashboard, isTrue);
    expect(moved.url, '/dashboard/#/partner/apply?type=busOperator');
  });

  testWidgets('the dashboard site opens on partner sign-in and keeps riders out', (tester) async {
    final state = await pumpApp(tester, size: const Size(1280, 900), mode: AppMode.dashboard);
    expect(find.text('Partner portal'), findsWidgets);
    expect(find.text('Continue with Google'), findsNothing);
    await go(tester, '/app');
    expect(tester.widget<ElsewherePage>(find.byType(ElsewherePage)).toDashboard, isFalse);

    await go(tester, '/login?portal=partner');
    await tester.runAsync(() => state.signIn(email: 'ops@abujametro.demo', password: DemoSeed.password, portal: Portal.partner));
    await tester.pumpAndSettle();
    expect(find.text('Operator dashboard'), findsWidgets);
  });

  test('website sign-ups are for admins only', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger);
    await expectLater(state.fetchWaitlist(), throwsA(isA<BackendException>()));
    await state.signOut();
    final admin = DemoSeed.demoAccounts.firstWhere((a) => a.$3 == UserRole.admin);
    await state.signIn(email: admin.$2, password: DemoSeed.password, portal: Portal.partner);
    final list = await state.fetchWaitlist();
    expect(list, isNotEmpty);
    expect(list.every((e) => e.name!.contains('(sample)')), isTrue, reason: 'demo rows are labelled');
    expect(list.expand((e) => e.seats).every((s) => s.time == '07:00'), isTrue);
  });
}
