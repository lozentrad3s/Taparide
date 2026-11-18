import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';

import 'test_support.dart';
import 'widget_test.dart' show signIn;

void main() {
  test('every corridor lists sourced operators, and sample operators are labelled', () {
    for (final r in DemoSeed.routes()) {
      expect(r.servedBy, isNotEmpty, reason: '${r.code} has no operators');
      for (final o in r.servedBy) {
        expect(o.source, startsWith('https://'), reason: '${r.code}: ${o.name}');
        expect(o.asOf, isNotEmpty);
      }
      final back = TransitRoute.fromJson(r.toJson());
      expect(back.servedBy.map((o) => o.toJson()).toList(), r.servedBy.map((o) => o.toJson()).toList());
    }
    final sample = DemoSeed.providers().where((p) => p.kind != ProviderKind.privateDriver);
    for (final p in sample) {
      expect(p.name, endsWith('(sample)'));
    }
  });

  testWidgets('route details shows who runs buses on the corridor, not as partners', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Log in').first);
    await tester.pumpAndSettle();
    await signIn(tester, 'aisha@taparide.demo');

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/ride/r01');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Who runs buses on this corridor today'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Pi-CNG & EV high-capacity CNG buses'), findsOneWidget);
    expect(find.textContaining('only with verified partners'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
