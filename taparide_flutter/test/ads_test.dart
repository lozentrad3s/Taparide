import 'package:flutter_test/flutter_test.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/house_ads.dart';
import 'package:taparide_flutter/core/models.dart';
import 'package:taparide_flutter/features/passenger/ad_strip.dart';

import 'test_support.dart';

void main() {
  test('the flyers show even when the server has no ads yet (no reward without the server)', () {
    final ads = HouseAds.merge(const []);
    expect(ads.map((a) => a.id), ['ad_events', 'ad_advertise']);
    expect(ads.every((a) => a.banner != null && a.reward == 0), isTrue);
  });

  test('a server ad keeps its reward and gets the flyer artwork', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger);
    final events = state.ads.firstWhere((a) => a.id == 'ad_events');
    expect(events.reward, greaterThan(0));
    expect(events.banner, 'assets/ads/events-together.png');
    expect(events.poster, 'assets/ads/event-ride.jpg');
    expect(state.ads.firstWhere((a) => a.id == 'ad_advertise').ctaLink, HouseAds.advertiseLink);
  });

  testWidgets('the rider home shows the ad flyer at the top', (tester) async {
    final state = await pumpApp(tester);
    await tester.runAsync(() => state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger));
    await tester.pumpAndSettle();
    expect(find.byType(AdArt), findsOneWidget);
    expect(find.textContaining('Watch the ad'), findsNothing); // no sponsored ads yet: rewards are off
    expect(tester.takeException(), isNull);
  });
}
