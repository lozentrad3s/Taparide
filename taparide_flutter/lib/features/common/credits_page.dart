import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/photos.dart';
import '../../shared/ui.dart';

class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final columns = MediaQuery.sizeOf(context).width >= 900 ? 3 : (MediaQuery.sizeOf(context).width >= 600 ? 2 : 1);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo credits'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          MaxWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Real photographs of Abuja and electric transport, used under open licences from Wikimedia Commons. Thank you to the photographers.', style: text.bodyLarge),
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.98,
                children: [
                  for (final c in photoCredits)
                    Panel(
                      padding: EdgeInsets.zero,
                      onTap: () => launchUrl(Uri.parse(c.source)),
                      semanticLabel: '${c.title} by ${c.author}, ${c.license}. Opens the source page.',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: PhotoView(c.photo)),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('${c.author} · ${c.license}', style: text.bodySmall),
                            const SizedBox(height: 4),
                            Text('View source', style: text.labelMedium?.copyWith(color: AppColors.forest)),
                          ]),
                        ),
                      ]),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Map data © OpenStreetMap contributors; map tiles © MapTiler or CARTO. Tap A Ride logo © its owners.', style: text.bodySmall),
            ]),
          ),
        ],
      ),
    );
  }
}
