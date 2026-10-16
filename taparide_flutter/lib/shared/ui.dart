import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/app_state.dart';
import '../core/backend/backend.dart';
import '../core/format.dart';
import '../core/photos.dart';

// ------------------------------------------------------------------ layout

bool isWide(BuildContext context, [double breakpoint = 900]) => MediaQuery.sizeOf(context).width >= breakpoint;

class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 1180, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final Widget child;
  final double width;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          // Fill the column so left-aligned content starts at the column edge.
          child: SizedBox(width: double.infinity, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// White working surface used for cards, lists and forms.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.lg), this.onTap, this.color = AppColors.surface, this.radius = AppRadius.lg, this.border = true, this.shadow = true, this.semanticLabel});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final double radius;
  final bool border;
  final bool shadow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border ? const BorderSide(color: AppColors.line) : BorderSide.none,
    );
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(onTap: onTap, customBorder: shape, child: content);
    }
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: shadow ? AppShadow.card : null),
        child: Material(color: color, shape: shape, clipBehavior: Clip.antiAlias, child: content),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction, this.subtitle});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      // The action link shares the title's baseline.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge),
                if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: text.bodySmall)],
              ],
            ),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ photos

/// A bundled photograph with a designed fallback if the asset cannot load.
class PhotoView extends StatelessWidget {
  const PhotoView(this.photo, {super.key, this.height, this.width, this.radius = 0, this.alignment = Alignment.center, this.overlay, this.semanticLabel});
  final AppPhoto photo;
  final double? height;
  final double? width;
  final double radius;
  final Alignment alignment;
  final Gradient? overlay;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      photo.asset,
      height: height,
      width: width,
      fit: BoxFit.cover,
      alignment: alignment,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic, child: child),
      errorBuilder: (context, error, stack) => Container(
        height: height,
        width: width,
        color: AppColors.mint,
        alignment: Alignment.center,
        child: const Icon(Icons.landscape_outlined, color: AppColors.forest, size: 32),
      ),
    );
    final layered = overlay == null
        ? image
        : Stack(fit: StackFit.passthrough, children: [image, Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: overlay)))]);
    return radius == 0 ? layered : ClipRRect(borderRadius: BorderRadius.circular(radius), child: layered);
  }
}

// ------------------------------------------------------------------ the route line (signature)

/// Transit-map style line: hollow origin stop, small intermediate stops, solid destination.
class RouteLine extends StatelessWidget {
  const RouteLine({super.key, this.stops = 2, this.color = AppColors.forest, this.vertical = false, this.thickness = 3, this.highlight});
  final int stops;
  final Color color;
  final bool vertical;
  final double thickness;

  /// Index of a stop to emphasise (e.g. the rider's current stop).
  final int? highlight;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _RouteLinePainter(stops: stops, color: color, vertical: vertical, thickness: thickness, highlight: highlight),
        size: vertical ? const Size(18, double.infinity) : const Size(double.infinity, 18),
      );
}

class _RouteLinePainter extends CustomPainter {
  _RouteLinePainter({required this.stops, required this.color, required this.vertical, required this.thickness, this.highlight});
  final int stops;
  final Color color;
  final bool vertical;
  final double thickness;
  final int? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 6.0;
    final start = vertical ? Offset(size.width / 2, r + 1) : Offset(r + 1, size.height / 2);
    final end = vertical ? Offset(size.width / 2, size.height - r - 1) : Offset(size.width - r - 1, size.height / 2);
    final line = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, line);

    final count = stops < 2 ? 2 : stops;
    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      final p = Offset.lerp(start, end, t)!;
      final isEnd = i == count - 1;
      final isStart = i == 0;
      if (isEnd) {
        canvas.drawCircle(p, r, Paint()..color = color);
        canvas.drawCircle(p, r * 0.38, Paint()..color = Colors.white);
      } else if (isStart || i == highlight) {
        canvas.drawCircle(p, r, Paint()..color = Colors.white);
        canvas.drawCircle(p, r - 1.2, Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6);
      } else {
        canvas.drawCircle(p, 3.6, Paint()..color = Colors.white);
        canvas.drawCircle(p, 3.6, Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RouteLinePainter old) =>
      old.stops != stops || old.color != color || old.vertical != vertical || old.highlight != highlight;
}

/// Origin and destination joined by the route line, used on every route card.
class RouteStrip extends StatelessWidget {
  const RouteStrip({super.key, required this.origin, required this.destination, this.stops = 2, this.dense = false, this.color = AppColors.forest, this.textColor});
  final Color? textColor;
  final String origin;
  final String destination;
  final int stops;
  final bool dense;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = (dense ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.titleMedium)?.copyWith(fontWeight: FontWeight.w700, color: textColor);
    return Semantics(
      label: '$origin to $destination',
      child: ExcludeSemantics(
        child: Row(
          children: [
            // Space is shared in proportion to name length so a short name never squeezes a long one.
            Flexible(flex: origin.length.clamp(1, 40), child: Text(origin, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
            SizedBox(width: dense ? 8 : 10),
            SizedBox(width: dense ? (14.0 * stops.clamp(2, 4)).clamp(40.0, 56.0) : 64, height: 18, child: RouteLine(stops: stops.clamp(2, 4), color: color)),
            SizedBox(width: dense ? 8 : 10),
            Flexible(flex: destination.length.clamp(1, 40), child: Text(destination, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ status + numbers

enum Tone { success, warning, danger, info, neutral, brand }

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = Tone.neutral, this.icon});
  final String label;
  final Tone tone;
  final IconData? icon;

  static (Color, Color) colors(Tone tone) => switch (tone) {
        Tone.success => (AppColors.mint, AppColors.leafText),
        Tone.warning => (AppColors.amberSoft, AppColors.amber),
        Tone.danger => (AppColors.redSoft, AppColors.red),
        Tone.info => (AppColors.blueSoft, AppColors.blue),
        Tone.neutral => (AppColors.surfaceSunk, AppColors.muted),
        Tone.brand => (AppColors.forest, Colors.white),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg, height: 1.1)),
        ],
      ),
    );
  }
}

class DeltaLabel extends StatelessWidget {
  const DeltaLabel(this.percent, {super.key, this.onDark = false});
  final int percent;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final color = onDark ? const Color(0xFFB8F0A0) : (up ? AppColors.leafText : AppColors.red);
    return Semantics(
      label: '${up ? 'up' : 'down'} ${percent.abs()} percent',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: color),
          const SizedBox(width: 2),
          Text('${percent.abs()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}

/// A labelled figure. On the forest field it matches the mockup's headline tiles.
class Figure extends StatelessWidget {
  const Figure({super.key, required this.label, required this.value, this.delta, this.onDark = false, this.icon, this.caption, this.large = false});
  final String label;
  final String value;
  final int? delta;
  final bool onDark;
  final IconData? icon;
  final String? caption;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final labelColor = onDark ? AppColors.onForestMuted : AppColors.muted;
    final valueColor = onDark ? Colors.white : AppColors.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: onDark ? AppColors.onForestMuted : AppColors.forest), const SizedBox(width: 6)],
          Flexible(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: labelColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: TextStyle(fontSize: large ? 32 : 26, fontWeight: FontWeight.w800, color: valueColor, height: 1, letterSpacing: -0.4, fontFeatures: tabular)),
        ),
        if (delta != null || caption != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            if (delta != null) DeltaLabel(delta!, onDark: onDark),
            if (delta != null && caption != null) const SizedBox(width: 6),
            if (caption != null) Flexible(child: Text(caption!, style: TextStyle(fontSize: 12, color: labelColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ],
      ],
    );
  }
}

/// Seven-day bar chart (FCTA ridership trend). Today is the solid bar.
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.values, required this.highlightIndex, this.labels, this.height = 170});
  final List<int> values;

  /// Day labels for each bar (defaults to Mon–Sun).
  final List<String>? labels;
  final int highlightIndex;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(1, (a, b) => a > b ? a : b);
    final labels = this.labels ?? Fmt.weekdays;
    final summary = [for (var i = 0; i < values.length; i++) '${labels[i]} ${Fmt.count(values[i])}'].join(', ');
    return Semantics(
      label: 'Ridership by day: $summary',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Tooltip(
                      message: '${labels[i]}: ${Fmt.count(values[i])} rides',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(Fmt.compact(values[i]), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: i == highlightIndex ? AppColors.forest : AppColors.muted, fontFeatures: tabular)),
                          const SizedBox(height: 4),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: values[i] / maxValue),
                            duration: Duration(milliseconds: 520 + i * 50),
                            curve: Curves.easeOutCubic,
                            builder: (context, t, _) => Container(
                              height: (height - 44) * t,
                              decoration: BoxDecoration(
                                color: i == highlightIndex ? AppColors.forest : AppColors.mintStrong,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(labels[i], style: TextStyle(fontSize: 12, fontWeight: i == highlightIndex ? FontWeight.w800 : FontWeight.w600, color: i == highlightIndex ? AppColors.ink : AppColors.muted)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ states

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.forest, size: 30),
          ),
          const SizedBox(height: 14),
          Text(title, style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: Text(message, style: text.bodyMedium, textAlign: TextAlign.center)),
          if (action != null) ...[const SizedBox(height: 16), FilledButton(onPressed: onAction, child: Text(action!))],
        ],
      ),
    );
  }
}

class LoadFailure extends StatelessWidget {
  const LoadFailure({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load this page',
        message: message,
        action: 'Try again',
        onAction: onRetry,
      );
}

/// Shows loading, error or content depending on the shared data state.
class DataGate extends StatelessWidget {
  const DataGate({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.dataState == LoadState.error && state.routes.isEmpty) {
      return Center(child: LoadFailure(message: state.dataError ?? 'Unknown error', onRetry: state.refresh));
    }
    if ((state.dataState == LoadState.loading || state.dataState == LoadState.idle) && state.routes.isEmpty) {
      return const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)));
    }
    return builder(context);
  }
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final backend = context.read<AppState>().backend;
    final live = !backend.isDemo;
    return Tooltip(
      message: live ? 'Connected to the live Supabase project' : 'Figures, people and organisations are illustrative demo data',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.12) : (live ? AppColors.mint : AppColors.amberSoft),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(live ? Icons.cloud_done_outlined : Icons.science_outlined, size: 13, color: onDark ? Colors.white : (live ? AppColors.leafText : AppColors.amber)),
          const SizedBox(width: 4),
          Text(backend.modeLabel, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: onDark ? Colors.white : (live ? AppColors.leafText : AppColors.amber))),
        ]),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initials, this.size = 40, this.color = AppColors.mint, this.textColor = AppColors.forest});
  final String initials;
  final double size;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(initials, style: TextStyle(fontWeight: FontWeight.w800, color: textColor, fontSize: size * 0.36)),
      );
}

class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.size = 44, this.color = AppColors.mint, this.iconColor = AppColors.forest, this.radius = 12});
  final IconData icon;
  final double size;
  final Color color;
  final Color iconColor;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
        child: Icon(icon, color: iconColor, size: size * 0.5),
      );
}

// ------------------------------------------------------------------ feedback

void showMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Row(children: [
      Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: error ? const Color(0xFFFFB4A9) : AppColors.leaf, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ]),
  ));
}

/// Runs a backend action, reporting failures in the user's language.
Future<T?> attempt<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final result = await action();
    if (success != null && context.mounted) showMessage(context, success);
    return result;
  } on BackendException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  } catch (_) {
    if (context.mounted) showMessage(context, 'Something went wrong. Please try again.', error: true);
  }
  return null;
}

/// Like [attempt] for actions without a result; returns whether it succeeded.
Future<bool> attemptOk(BuildContext context, Future<void> Function() action, {String? success}) async {
  final done = await attempt<bool>(context, () async {
    await action();
    return true;
  }, success: success);
  return done ?? false;
}

/// Back arrow that still works when a page was opened from a link (no history).
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.fallback = '/app', this.color});
  final String fallback;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Back',
        color: color,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () {
          final router = GoRouter.of(context);
          router.canPop() ? router.pop() : router.go(fallback);
        },
      );
}
