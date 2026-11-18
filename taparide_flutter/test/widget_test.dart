import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taparide_flutter/core/backend/backend.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';

import 'test_support.dart';

Future<void> signIn(WidgetTester tester, String email, {bool partner = false}) async {
  if (partner) {
    await tester.tap(find.text('Partner portal').first);
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), DemoSeed.password);
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('passenger signs in, books a seat and sees it in their trips', (tester) async {
    final state = await pumpApp(tester);
    expect(find.text('Next'), findsOneWidget, reason: 'opens on the onboarding');

    await tester.tap(find.text('Log in').first);
    await tester.pumpAndSettle();
    await signIn(tester, 'aisha@taparide.demo');

    expect(find.textContaining(', Aisha'), findsOneWidget);
    final balanceBefore = state.wallet!.balance;

    final route = state.routeById('r01')!;
    final departure = route.upcomingDepartures(state.now).first;
    final booking = await tester.runAsync(() => state.bookTransit(route, departure, PaymentMethod.tapCard));
    await tester.pumpAndSettle();

    expect(booking!.status, BookingStatus.confirmed);
    expect(state.wallet!.balance, balanceBefore - route.fare);
    expect(state.upcomingTrips.map((b) => b.id), contains(booking.id));

    await tester.tap(find.text('My Trips').last);
    await tester.pumpAndSettle();
    expect(find.text('Upcoming (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partner accounts cannot use passenger sign-in', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Log in').first);
    await tester.pumpAndSettle();
    await signIn(tester, 'ops@abujametro.demo');
    expect(find.textContaining('partner account'), findsOneWidget);
  });

  testWidgets('operator opens the operator dashboard with live bookings', (tester) async {
    final state = await pumpApp(tester, size: const Size(1440, 1000));
    await tester.tap(find.text('Log in').first);
    await tester.pumpAndSettle();
    await signIn(tester, 'ops@abujametro.demo', partner: true);

    expect(find.text('Operator Dashboard'), findsOneWidget);
    expect(find.text('Abuja Metro Bus Co. (sample) · Bus operator'), findsOneWidget);
    expect(find.text('Total Trips'), findsOneWidget);
    expect(state.partnerBookings, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  test('backend enforces roles, not just the UI', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'ops@abujametro.demo', password: DemoSeed.password, portal: Portal.partner);
    await expectLater(
      () => backend.setProviderStatus(DemoSeed.pKubwa, Verification.verified),
      throwsA(isA<BackendException>().having((e) => e.kind, 'kind', BackendErrorKind.permission)),
    );
    await expectLater(() => backend.fetchUsers(), throwsA(isA<BackendException>()));

    await state.signOut();
    await state.signIn(email: 'transport@fcta.demo', password: DemoSeed.password, portal: Portal.partner);
    final approved = await backend.setProviderStatus(DemoSeed.pKubwa, Verification.verified);
    expect(approved.status, Verification.verified);
    expect((await backend.fetchAuditLog()).first.action, 'Approved provider');
    await expectLater(
      () => backend.setProviderStatus(DemoSeed.pMetro, Verification.suspended),
      throwsA(isA<BackendException>()),
      reason: 'only platform admins may suspend providers',
    );
  });

  test('a passenger booking reaches the FCTA ridership figures', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger);
    final before = (await backend.fetchMyBookings()).length;
    expect(before, 7);
    final route = state.routeById('r02')!;
    await state.bookTransit(route, route.upcomingDepartures(state.now).first, PaymentMethod.qr);
    await state.signOut();

    await state.signIn(email: 'transport@fcta.demo', password: DemoSeed.password, portal: Portal.partner);
    final fcta = state.fctaDashboard()!;
    final now = state.now;
    final seededToday = DemoSeed.bookings(now).where((b) => b.createdAt.year == now.year && b.createdAt.month == now.month && b.createdAt.day == now.day).length;
    expect(fcta.bookingsToday, seededToday + 1);
    expect(fcta.totalRidership, DemoSeed.baselines.totalRidership + seededToday + 1);
    expect(fcta.verifiedVehicles, 1204);
    expect(fcta.activeRoutes, 32);
    expect(backend.isDemo, isTrue);
  });

  test('insufficient balance is refused and suspended providers stop taking bookings', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger);
    // Spend the balance down below the fare of the Nyanya – Jabi Garage bus (₦1,700).
    final cheap = state.routeById('r07')!;
    for (final at in cheap.upcomingDepartures(state.now)) {
      if (state.wallet!.balance < 1700) break;
      await state.bookTransit(cheap, at, PaymentMethod.tapCard);
    }
    final long = state.routeById('r08')!;
    expect(state.wallet!.balance, lessThan(long.fare));
    await expectLater(
      () => state.bookTransit(long, long.upcomingDepartures(state.now).first, PaymentMethod.tapCard),
      throwsA(isA<BackendException>().having((e) => e.kind, 'kind', BackendErrorKind.insufficientFunds)),
    );
    expect(state.bookableRoutes.any((r) => r.providerId == DemoSeed.pKubwa), isFalse);
  });
}
