import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../shared/mascot/mascot.dart';
import '../../shared/ui.dart';
import '../../shared/web_frame/web_frame.dart';

/// FindMe AI, the smart safety map (nearby places, live traffic, incidents, SOS), inside Tap A Ride.
const findMeUrl = 'https://findme-ai-lozen-s-projects.vercel.app/';

class NearbyPage extends StatelessWidget {
  const NearbyPage({super.key, this.category});
  final String? category;

  Future<void> _openOutside() => launchUrl(Uri.parse(findMeUrl), mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/app'),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nearby & safety', style: text.titleMedium),
          Text(category == null ? 'Powered by FindMe AI' : 'Looking for: $category · FindMe AI', style: text.bodySmall),
        ]),
        actions: [
          IconButton(tooltip: 'Open in a new tab', onPressed: _openOutside, icon: const Icon(Icons.open_in_new_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: WebFrame(
        url: findMeUrl,
        title: 'FindMe AI map',
        fallback: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Mascot(mood: MascotMood.wave, size: 140),
              const SizedBox(height: 12),
              Text('Nearby places, live traffic and SOS', style: text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('FindMe AI opens in your browser.', style: text.bodyMedium?.copyWith(color: AppColors.muted), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _openOutside, icon: const Icon(Icons.map_rounded), label: const Text('Open FindMe AI')),
            ]),
          ),
        ),
      ),
    );
  }
}
