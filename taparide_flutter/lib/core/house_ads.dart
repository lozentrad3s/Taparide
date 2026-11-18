import 'package:flutter/painting.dart' show Color;

import 'live_models.dart';

/// Tap A Ride's own ad flyers, built into the app so the header slot always has something to
/// show (even before the ads table exists on the server). When the server has an ad with the
/// same id, the server's copy wins (it carries the watch-to-earn reward) and gets this artwork.
abstract final class HouseAds {
  static const advertiseLink =
      'mailto:partnership@taparide.com?subject=Advertising%20on%20Tap%20A%20Ride';

  static const all = [
    PromoAd(
      id: 'ad_events',
      sponsor: 'Tap A Ride Events',
      headline: 'Get to events together',
      body:
          'Book a seat on an event bus from your area. Share the ride, travel safe and save more.',
      ctaLabel: 'Join Event Ride',
      ctaLink: '/events',
      colour: Color(0xFF0B5A3A),
      icon: 'celebration',
      reward: 0,
      seconds: 15,
      house: true,
      banner: 'assets/ads/events-together.png',
      poster: 'assets/ads/event-ride.jpg',
    ),
    PromoAd(
      id: 'ad_advertise',
      sponsor: 'Tap A Ride',
      headline: 'Put your brand in front of Abuja commuters',
      body:
          'Header slots and sponsored rides seen on every trip. Write to partnership@taparide.com.',
      ctaLabel: 'Advertise now',
      ctaLink: advertiseLink,
      colour: Color(0xFF0B5A3A),
      icon: 'campaign',
      reward: 0,
      seconds: 15,
      house: true,
      banner: 'assets/ads/advertise.png',
    ),
  ];

  /// Our flyers first (with the server's reward when it has the same ad), then the server's other ads.
  static List<PromoAd> merge(List<PromoAd> server) {
    final byId = {for (final a in server) a.id: a};
    return [
      for (final h in all)
        if (byId[h.id] case final s?)
          s.copyWith(
              banner: s.banner ?? h.banner,
              poster: s.poster ?? h.poster,
              ctaLink: h.ctaLink,
              ctaLabel: h.ctaLabel)
        else
          h,
      for (final a in server)
        if (!all.any((h) => h.id == a.id)) a,
    ];
  }
}
