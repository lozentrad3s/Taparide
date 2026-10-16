import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';

/// Standard portal page: title row, then content in a centred column.
class PortalScaffold extends StatelessWidget {
  const PortalScaffold({super.key, required this.title, this.subtitle, this.leading, this.actions = const [], required this.children});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final wide = isWide(context, 1024);
    final pad = wide ? 32.0 : 16.0;
    return ColoredBox(
      color: AppColors.ground,
      child: DataGate(
        builder: (context) => RefreshIndicator(
          color: AppColors.forest,
          onRefresh: state.refresh,
          child: ListView(
            padding: EdgeInsets.fromLTRB(0, wide ? 26 : 16, 0, 40),
            children: [
              MaxWidth(
                width: 1320,
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 12,
                    spacing: 16,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (leading != null) ...[leading!, const SizedBox(width: 14)],
                        Flexible(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(title, style: wide ? text.headlineLarge : text.headlineMedium),
                            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: text.bodyMedium)],
                          ]),
                        ),
                      ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        ...actions,
                        const SizedBox(width: 8),
                        const DemoBadge(),
                        if (wide) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Refresh data',
                            onPressed: state.dataState == LoadState.loading ? null : state.refresh,
                            icon: state.dataState == LoadState.loading
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ]),
                    ],
                  ),
                  const SizedBox(height: 22),
                  ...children,
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays out children in a responsive grid of equal columns.
class Cols extends StatelessWidget {
  const Cols({super.key, required this.children, this.min = 240, this.gap = 14, this.max = 4});
  final List<Widget> children;
  final double min;
  final double gap;
  final int max;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final count = ((c.maxWidth + gap) / (min + gap)).floor().clamp(1, max);
        final width = (c.maxWidth - gap * (count - 1)) / count;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final child in children) SizedBox(width: width, child: child)]);
      });
}

class FigureCard extends StatelessWidget {
  const FigureCard({super.key, required this.label, required this.value, this.delta, this.icon, this.caption, this.onTap});
  final String label;
  final String value;
  final int? delta;
  final IconData? icon;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Panel(
        onTap: onTap,
        padding: const EdgeInsets.all(18),
        child: Figure(label: label, value: value, delta: delta, icon: icon, caption: caption),
      );
}

/// The mockup's deep-green headline panel (two figures side by side).
class ForestFigures extends StatelessWidget {
  const ForestFigures({super.key, required this.figures});
  final List<Figure> figures;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF0E6B45), AppColors.forestDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < figures.length; i++) ...[
              if (i > 0) VerticalDivider(width: 36, color: Colors.white.withValues(alpha: 0.2)),
              Expanded(child: figures[i]),
            ],
          ]),
        ),
      );
}

class PanelTitle extends StatelessWidget {
  const PanelTitle(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleLarge),
            if (subtitle != null) Text(subtitle!, style: text.bodySmall),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// A column definition for [DataList].
class Col<T> {
  const Col(this.label, this.cell, {this.flex = 2, this.numeric = false});
  final String label;
  final Widget Function(T item) cell;
  final int flex;
  final bool numeric;
}

/// Table on wide screens; stacked label/value cards on phones.
class DataList<T> extends StatelessWidget {
  const DataList({super.key, required this.items, required this.columns, this.trailing, this.empty, this.onTap, this.titleOf});
  final List<T> items;
  final List<Col<T>> columns;
  final Widget Function(T item)? trailing;
  final Widget? empty;
  final ValueChanged<T>? onTap;

  /// Main line for the phone layout (defaults to the first column).
  final Widget Function(T item)? titleOf;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return empty ?? const EmptyState(icon: Icons.inbox_rounded, title: 'Nothing here yet', message: 'Records will appear here as they are created.');
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 760) {
        return Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            Container(
              color: AppColors.surfaceSunk,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                for (final col in columns)
                  Expanded(
                    flex: col.flex,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(col.label.toUpperCase(), style: text.labelSmall?.copyWith(letterSpacing: 0.6), textAlign: col.numeric ? TextAlign.right : TextAlign.left),
                    ),
                  ),
                if (trailing != null) const SizedBox(width: 160),
              ]),
            ),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(),
              InkWell(
                onTap: onTap == null ? null : () => onTap!(items[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Row(children: [
                      for (final col in columns)
                        Expanded(
                          flex: col.flex,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Align(alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft, child: col.cell(items[i])),
                          ),
                        ),
                      if (trailing != null) SizedBox(width: 160, child: Align(alignment: Alignment.centerRight, child: trailing!(items[i]))),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        );
      }
      return Column(children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              onTap: onTap == null ? null : () => onTap!(item),
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DefaultTextStyle.merge(style: text.titleSmall, child: (titleOf ?? columns.first.cell)(item)),
                const SizedBox(height: 8),
                for (final col in columns.skip(titleOf == null ? 1 : 0))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: 110, child: Text(col.label, style: text.bodySmall)),
                      Expanded(child: Align(alignment: Alignment.centerLeft, child: col.cell(item))),
                    ]),
                  ),
                if (trailing != null) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerRight, child: trailing!(item))],
              ]),
            ),
          ),
      ]);
    });
  }
}

/// Lets FCTA and admins look at any provider's dashboard.
class ProviderPicker extends StatelessWidget {
  const ProviderPicker({super.key, required this.providers, required this.selected, required this.onChanged});
  final List<TransportProvider> providers;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Provider', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          items: [for (final p in providers) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      );
}

Tone verificationTone(Verification v) => switch (v) {
      Verification.verified => Tone.success,
      Verification.pending => Tone.warning,
      Verification.suspended => Tone.danger,
    };

Tone vehicleTone(VehicleStatus s) => switch (s) {
      VehicleStatus.active => Tone.success,
      VehicleStatus.onTrip => Tone.info,
      VehicleStatus.charging => Tone.info,
      VehicleStatus.maintenance => Tone.warning,
      VehicleStatus.inactive => Tone.danger,
    };

/// Horizontal share bar, e.g. active / maintenance / inactive vehicles.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.parts, this.height = 10});
  final List<(int, Color)> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<int>(0, (a, p) => a + p.$1);
    if (total == 0) return SizedBox(height: height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Row(children: [
          for (final p in parts)
            if (p.$1 > 0) Expanded(flex: p.$1, child: Container(color: p.$2)),
        ]),
      ),
    );
  }
}

class LegendRow extends StatelessWidget {
  const LegendRow({super.key, required this.color, required this.label, required this.value, this.trailing});
  final Color color;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.ink))),
        Text(value, style: text.titleSmall?.copyWith(fontFeatures: tabular)),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

String moneyCell(int amount) => Fmt.naira(amount);
