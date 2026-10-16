// Renders the main screens to PNGs for design review.
// Run: flutter test test/screens --update-goldens --dart-define=SCREENS=true
@Tags(['screens'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taparide_flutter/app/app.dart';
import 'package:taparide_flutter/core/app_state.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';

import '../test_support.dart';

const _enabled = bool.fromEnvironment('SCREENS');

const phone = Size(390, 844);
const desktop = Size(1440, 1000);

Future<void> _settleImages(WidgetTester tester) async {
  for (var pass = 0; pass < 2; pass++) {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = (element.widget as Image).image;
        await precacheImage(image, element);
      }
    });
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpAndSettle();
}

Future<AppState> _app(WidgetTester tester, Size size, {String? email, Portal portal = Portal.passenger}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(loadAppFonts);
  final (state, _) = (await tester.runAsync(freshState))!;
  if (email != null) {
    await tester.runAsync(() => state.signIn(email: email, password: DemoSeed.password, portal: portal));
  }
  await tester.pumpWidget(TapARideApp(state: state));
  await tester.pumpAndSettle();
  return state;
}

Future<void> _go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _settleImages(tester);
  await expectLater(find.byType(TapARideApp), matchesGoldenFile('out/$name.png'));
}

void main() {
  if (!_enabled) {
    test('screens (skipped: pass --dart-define=SCREENS=true)', () {});
    return;
  }

  testWidgets('landing full page', (t) async {
    await _app(t, const Size(390, 6400));
    await _shot(t, 'mobile_full');
    t.view.physicalSize = const Size(1440, 4400);
    await t.pumpAndSettle();
    await _shot(t, 'landing_desktop_full');
  });

  testWidgets('login', (t) async {
    await _app(t, desktop);
    await _go(t, '/login');
    await _shot(t, 'login_desktop');
    await _go(t, '/login?portal=partner');
    await _shot(t, 'portal_login_desktop');
  });

  testWidgets('rider phone screens', (t) async {
    final state = await _app(t, phone, email: 'aisha@taparide.demo');
    await _shot(t, 'rider_home_phone');
    await t.drag(find.byType(ListView).first, const Offset(0, -560));
    await t.pumpAndSettle();
    await _shot(t, 'rider_home_phone_scrolled');
    await t.drag(find.byType(ListView).first, const Offset(0, -1200));
    await t.pumpAndSettle();
    await _shot(t, 'rider_home_phone_bottom');
    await _go(t, '/app/routes');
    await _shot(t, 'rider_routes_phone');
    await _go(t, '/ride/r01');
    await _shot(t, 'rider_route_details_phone');
    final route = state.routeById('r01')!;
    final at = route.upcomingDepartures(state.now)[1];
    await _go(t, Uri(path: '/ride/r01/pay', queryParameters: {'at': at.toUtc().toIso8601String()}).toString());
    await _shot(t, 'rider_payment_phone');
    final booking = (await t.runAsync(() => state.bookTransit(route, at, PaymentMethod.tapCard)))!;
    await _go(t, '/ticket/${booking.id}');
    await _shot(t, 'rider_ticket_phone');
    await _go(t, '/app/trips');
    await _shot(t, 'rider_trips_phone');
    await _go(t, '/app/profile');
    await _shot(t, 'rider_profile_phone');
    await _go(t, '/ev');
    await _shot(t, 'rider_ev_phone');
    await _go(t, '/tag-along');
    await _shot(t, 'rider_tag_along_phone');
  });

  testWidgets('rider desktop screens', (t) async {
    await _app(t, desktop, email: 'aisha@taparide.demo');
    await _shot(t, 'rider_home_desktop');
    await _go(t, '/ride/r02');
    await _shot(t, 'rider_route_details_desktop');
    await _go(t, '/tag-along');
    await _shot(t, 'rider_tag_along_desktop');
  });

  testWidgets('admin portal', (t) async {
    await _app(t, desktop, email: 'admin@taparide.demo', portal: Portal.partner);
    await _shot(t, 'admin_overview_desktop');
    for (final page in ['insights', 'applications', 'fcta', 'operator', 'fleet', 'providers', 'evs', 'routes', 'vehicles', 'verification', 'users']) {
      await _go(t, '/portal/$page');
      await _shot(t, 'admin_${page}_desktop');
    }
  });

  testWidgets('partner phone screens', (t) async {
    await _app(t, phone, email: 'ops@abujametro.demo', portal: Portal.partner);
    await _shot(t, 'operator_phone');
  });

  testWidgets('fcta phone', (t) async {
    await _app(t, phone, email: 'transport@fcta.demo', portal: Portal.partner);
    await _shot(t, 'fcta_phone');
  });

  testWidgets('partner apply', (t) async {
    await _app(t, phone);
    await _go(t, '/partner/apply');
    await _shot(t, 'partner_apply_phone');
  });

  testWidgets('partner status', (t) async {
    await _app(t, phone, email: 'musa@taparide.demo');
    await _go(t, '/partner/status');
    await _shot(t, 'partner_status_phone');
  });

  testWidgets('insights as admin', (t) async {
    await _app(t, desktop, email: 'admin@taparide.demo', portal: Portal.partner);
    await _go(t, '/portal/insights?provider=${DemoSeed.pMetro}');
    await _shot(t, 'insights_metro_desktop');
  });

  testWidgets('insights as fleet owner', (t) async {
    await _app(t, phone, email: 'fleet@greenfleet.demo', portal: Portal.partner);
    await _go(t, '/portal/insights');
    await _shot(t, 'insights_fleet_phone');
  });
}
