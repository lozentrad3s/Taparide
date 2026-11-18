import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';

//// Spacing used on every portal page, so panels line up across dashboards.
abstract final class PortalSpace {
  static const gap = 16.0;
  static const section = 28.0;
}

/// Standard portal page: header (optional icon, title, subtitle, actions), then content in a centred column.
class PortalScaffold extends StatelessWidget {
  const PortalScaffold({super.key, required this.title, this.subtitle, this.leading, this.icon, this.actions = const [], required this.children});
  final String title;
  final String? subtitle;

  /// A custom widget before the title. Prefer [icon] for the standard badge.
  final Widget? leading;
  final IconData? icon;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final wide = isWide(context, 1024);
    final pad = wide ? 32.0 : 16.0;
    final badge = leading ??
        (icon == null
            ? null
            : Container(
                width: wide ? 44 : 38,
                height: wide ? 44 : 38,
                decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Icon(icon, color: AppLime.lime, size: wide ? 22 : 20),
              ));
    final heading = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (badge != null) ...[badge, const SizedBox(width: 14)],
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: (wide ? text.headlineMedium : text.headlineSmall)?.copyWith(letterSpacing: -0.3)),
          if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, style: text.bodyMedium?.copyWith(color: AppColors.muted))],
        ]),
      ),
    ]);
    final toolbar = actions.isEmpty ? null : Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.end, children: actions);
    return ColoredBox(
      color: AppColors.ground,
      child: DataGate(
        builder: (context) => RefreshIndicator(
          color: AppColors.forest,
          onRefresh: state.refresh,
          child: ListView(
            padding: EdgeInsets.fromLTRB(0, wide ? 28 : 18, 0, 96),
            children: [
              MaxWidth(
                width: 1320 + pad * 2,
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  LayoutBuilder(
                    builder: (context, c) => toolbar != null && c.maxWidth >= 760
                        ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: heading), const SizedBox(width: 16), Flexible(child: toolbar)])
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [heading, if (toolbar != null) ...[const SizedBox(height: 14), Align(alignment: Alignment.centerLeft, child: toolbar)]]),
                  ),
                  SizedBox(height: wide ? 24 : 18),
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
  const Cols({super.key, required this.children, this.min = 240, this.gap = PortalSpace.gap, this.max = 4});
  final List<Widget> children;
  final double min;
  final double gap;
  final int max;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final count = ((c.maxWidth + gap) / (min + gap)).floor().clamp(1, max);
        // Rows of equal-height cells so figures and panels line up.
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += count) {
          final cells = children.sublist(start, (start + count).clamp(0, children.length));
          rows.add(IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: i < cells.length ? cells[i] : const SizedBox.shrink()),
              ],
            ]),
          ));
        }
        return Column(children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) SizedBox(height: gap), rows[i]],
        ]);
      });
}

/// Two panels side by side on wide screens, stacked on narrow ones.
class TwoUp extends StatelessWidget {
  const TwoUp({super.key, required this.left, required this.right, this.leftFlex = 3, this.rightFlex = 2, this.breakpoint = 920});
  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double breakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => c.maxWidth >= breakpoint
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: leftFlex, child: left),
                const SizedBox(width: PortalSpace.gap),
                Expanded(flex: rightFlex, child: right),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: PortalSpace.gap), right]),
      );
}

/// A heading that starts a group of panels on a long dashboard.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: PortalSpace.section - PortalSpace.gap, bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleLarge?.copyWith(letterSpacing: -0.2)),
            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: text.bodySmall)],
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Up or down change as a small coloured chip.
class DeltaChip extends StatelessWidget {
  const DeltaChip(this.percent, {super.key});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    return Semantics(
      label: '${up ? 'up' : 'down'} ${percent.abs()} percent',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 2, 7, 2),
          decoration: BoxDecoration(color: up ? AppColors.mint : AppColors.redSoft, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: up ? AppColors.leafText : AppColors.red),
            const SizedBox(width: 2),
            Text('${percent.abs()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: up ? AppColors.leafText : AppColors.red, fontFeatures: tabular)),
          ]),
        ),
      ),
    );
  }
}

/// A KPI tile: label, big tabular figure, optional change and caption.
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
        radius: AppRadius.md,
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        semanticLabel: '$label: $value',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted, height: 1.25), maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(icon, size: 16, color: AppColors.forest),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.05, letterSpacing: -0.6, fontFeatures: tabular)),
          ),
          if (delta != null || caption != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (delta != null) ...[DeltaChip(delta!), const SizedBox(width: 6)],
              if (caption != null) Flexible(child: Text(caption!, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.25), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ]),
      );
}

/// The deep-green headline panel (figures side by side).
class ForestFigures extends StatelessWidget {
  const ForestFigures({super.key, required this.figures});
  final List<Figure> figures;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF0B5A3A), AppColors.forestDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < figures.length; i++) ...[
              if (i > 0) VerticalDivider(width: 36, color: Colors.white.withValues(alpha: 0.16)),
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: text.bodySmall)],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

/// A titled white panel: the standard container for charts and lists on a dashboard.
class DashPanel extends StatelessWidget {
  const DashPanel({super.key, required this.title, this.subtitle, this.trailing, required this.children, this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 20)});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Panel(
        radius: AppRadius.md,
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [PanelTitle(title, subtitle: subtitle, trailing: trailing), ...children]),
      );
}

/// A compact text link for panel headers ("View all").
class PanelLink extends StatelessWidget {
  const PanelLink(this.label, {super.key, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 10), textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label), const SizedBox(width: 2), const Icon(Icons.arrow_forward_rounded, size: 15)]),
      );
}

/// Two-to-four way switch (e.g. "Estimated riders" / "App bookings").
class PillTabs<T> extends StatelessWidget {
  const PillTabs({super.key, required this.values, required this.labelOf, required this.selected, required this.onChanged});
  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.surfaceSunk, borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: AppColors.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final v in values)
            Semantics(
              selected: v == selected,
              button: true,
              child: InkWell(
                onTap: () => onChanged(v),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: v == selected ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: v == selected ? const [BoxShadow(color: Color(0x140B2A1A), blurRadius: 3, offset: Offset(0, 1))] : null,
                  ),
                  child: Text(labelOf(v), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: v == selected ? AppColors.ink : AppColors.muted)),
                ),
              ),
            ),
        ]),
      );
}

/// Filter chips in the portal style (selected = forest with white text).
class FilterBar<T> extends StatelessWidget {
  const FilterBar({super.key, required this.values, required this.labelOf, required this.selected, required this.onChanged});
  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in values)
          ChoiceChip(
            label: Text(labelOf(v)),
            selected: v == selected,
            showCheckmark: false,
            labelStyle: TextStyle(color: v == selected ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700, fontSize: 13),
            onSelected: (_) => onChanged(v),
          ),
      ]);
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
    if (items.isEmpty)
      return empty ?? const EmptyState(icon: Icons.inbox_rounded, title: 'Nothing here yet', message: 'Records will appear here as they are created.');
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
                      child: Text(col.label.toUpperCase(),
                          style: text.labelSmall?.copyWith(letterSpacing: 0.6), textAlign: col.numeric ? TextAlign.right : TextAlign.left),
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
