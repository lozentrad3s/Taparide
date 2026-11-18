import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';

import 'test_support.dart';

void main() {
  testWidgets('Abuja Tech Week is listed in the app with free buses booked on the website', (tester) async {
    final state = await pumpApp(tester);
    await tester.runAsync(() => state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger));
    await tester.pumpAndSettle();
    final event = state.eventById('ev_techweek');
    expect(event, isNotNull);
    expect(event!.sponsored, isTrue);

    GoRouter.of(tester.element(find.byType(Navigator).first)).go('/events/ev_techweek');
    await tester.pumpAndSettle();
    expect(find.text('Abuja Tech Week 2026'), findsOneWidget);
    expect(find.text('Tap A Ride is the official ride partner'), findsOneWidget);
    expect(find.text('Reserve your free seat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
