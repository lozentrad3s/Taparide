import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../core/photos.dart';
import 'ui.dart';

/// Which rider features are open. Launch focus: event rides, tap to pay and Tag Along.
/// The rest stays in the app as "Coming soon" until operators and vehicles are on board;
/// flipping a flag here opens the full flow again (nothing was removed).
abstract final class Launch {
  static const electric = false;
  static const liveMap = false;
}

/// Small "Soon" tag for tiles and list rows.
class SoonTag extends StatelessWidget {
  const SoonTag({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.16) : AppColors.amberSoft,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          'Soon',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onDark ? Colors.white : AppColors.amber, fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      );
}

/// A whole page for a feature that is not open yet: what it will do, and what works today.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, required this.icon, required this.message, this.photo, this.photoLabel});
  final String title;
  final IconData icon;
  final String message;
  final AppPhoto? photo;
  final String? photoLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: AspectRatio(aspectRatio: 16 / 10, child: PhotoView(photo!, semanticLabel: photoLabel ?? title)),
                  ),
                const SizedBox(height: 22),
                Row(children: [
                  IconBadge(icon, size: 44),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: text.headlineSmall)),
                  const SoonTag(),
                ]),
                const SizedBox(height: 10),
                Text(message, style: text.bodyLarge?.copyWith(color: AppColors.inkSoft)),
                const SizedBox(height: 22),
                Text('Open today', style: text.labelLarge?.copyWith(color: AppColors.muted)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ActionChip(avatar: const Icon(Icons.celebration_rounded, size: 18), label: const Text('Event rides'), onPressed: () => context.push('/events')),
                  ActionChip(avatar: const Icon(Icons.groups_rounded, size: 18), label: const Text('Tag Along'), onPressed: () => context.push('/tag-along')),
                  ActionChip(avatar: const Icon(Icons.home_rounded, size: 18), label: const Text('Home'), onPressed: () => context.go('/app')),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
