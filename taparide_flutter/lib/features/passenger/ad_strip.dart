import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../shared/ticking.dart';

void _openAdLink(BuildContext context, PromoAd ad) {
  final link = ad.ctaLink;
  if (link == null || link.isEmpty) return;
  if (link.startsWith('/')) {
    context.push(link);
  } else {
    launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  }
}

/// A slim sponsored slot in the rider header. One ad shows at a time and rotates, so many
/// riders see the same slot at once without anything covering what they're doing.
class AdStrip extends StatefulWidget {
  const AdStrip({super.key});

  @override
  State<AdStrip> createState() => _AdStripState();
}

class _AdStripState extends State<AdStrip> {
  Timer? _timer;
  int _index = 0;
  final _counted = <String>{};

  @override
  void initState() {
    super.initState();
    if (LiveTicking.enabled) {
      _timer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (mounted) setState(() => _index++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ads = state.ads;
    if (ads.isEmpty) return const SizedBox.shrink();
    final ad = ads[_index % ads.length];
    if (_counted.add(ad.id)) state.countAdImpressions([ad]);
    final text = Theme.of(context).textTheme;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
      child: Material(
        key: ValueKey(ad.id),
        color: ad.colour,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openAdLink(context, ad),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                child: Icon(ad.iconData, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(ad.house ? 'Tap A Ride promotion' : 'Sponsored · ${ad.sponsor}', style: text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.78), letterSpacing: 0.3)),
                  Text(ad.headline, style: text.titleSmall?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: 8),
              if (ad.reward > 0)
                FilledButton.icon(
                  onPressed: () => showAdWatchSheet(context, ad),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: ad.colour,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                  label: Text('Earn ${Fmt.naira(ad.reward)}'),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Plays an ad in full; the server times the view and pays ride credit at the end.
Future<void> showAdWatchSheet(BuildContext context, PromoAd ad) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdPlayer(ad: ad),
    );

class _AdPlayer extends StatefulWidget {
  const _AdPlayer({required this.ad});
  final PromoAd ad;

  @override
  State<_AdPlayer> createState() => _AdPlayerState();
}

class _AdPlayerState extends State<_AdPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this, duration: Duration(seconds: widget.ad.seconds));
  AdView? _view;
  String? _error;
  AdReward? _reward;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _view = await context.read<AppState>().startAdView(widget.ad);
      if (!mounted) return;
      _progress.forward().whenComplete(_claim);
      setState(() {});
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _claim() async {
    final view = _view;
    if (view == null || !mounted || _claiming) return;
    setState(() => _claiming = true);
    try {
      final reward = await context.read<AppState>().claimAdReward(view);
      if (mounted) setState(() => _reward = reward);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final text = Theme.of(context).textTheme;
    final done = _reward != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: ad.colour,
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(ad.house ? 'Tap A Ride promotion' : 'Sponsored · ${ad.sponsor}', style: text.labelMedium?.copyWith(color: Colors.white70)),
                const Spacer(),
                IconButton(
                  tooltip: done ? 'Close' : 'Skip (no reward)',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ]),
              const SizedBox(height: 8),
              Icon(ad.iconData, color: Colors.white, size: 56),
              const SizedBox(height: 16),
              Text(ad.headline, style: text.headlineSmall?.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              Text(ad.body, style: text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: _error != null
                ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(_error!, style: text.bodyMedium?.copyWith(color: AppColors.red, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                  ])
                : done
                    ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.leafText),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _reward!.reward > 0 ? '${Fmt.naira(_reward!.reward)} ride credit added. Balance ${Fmt.naira(_reward!.balance)}.' : 'Thanks for watching. You\'ve earned today\'s rewards already.',
                              style: text.titleMedium,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(_reward!.left > 0 ? '${_reward!.left} more reward${_reward!.left == 1 ? '' : 's'} available today.' : 'New rewards tomorrow.', style: text.bodySmall),
                        const SizedBox(height: 14),
                        Row(children: [
                          if (ad.ctaLink != null)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _openAdLink(context, ad);
                                },
                                child: Text(ad.ctaLabel),
                              ),
                            ),
                          if (ad.ctaLink != null) const SizedBox(width: 10),
                          Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))),
                        ]),
                      ])
                    : AnimatedBuilder(
                        animation: _progress,
                        builder: (context, _) {
                          final left = (ad.seconds * (1 - _progress.value)).ceil();
                          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(value: _view == null ? null : _progress.value, minHeight: 8, backgroundColor: AppColors.surfaceSunk, color: ad.colour),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _claiming ? 'Adding your ride credit…' : (_view == null ? 'Starting…' : 'Watch for $left more second${left == 1 ? '' : 's'} to earn ${Fmt.naira(ad.reward)} ride credit'),
                              style: text.bodyMedium,
                            ),
                          ]);
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
