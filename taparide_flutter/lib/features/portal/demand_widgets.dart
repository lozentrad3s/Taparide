import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../core/format.dart';
import '../../shared/download/download.dart';
import '../../shared/ui.dart';
import 'portal_widgets.dart';

/// Hours shown on demand charts (first and last departures in Abuja run 05:00–22:00).
const _from = 5, _to = 22;

/// Sequential scale for heatmaps: pale (few riders) to forest (many).
Color demandColor(double t) {
  if (t <= 0) return const Color(0xFFF1F5F2);
  const stops = [Color(0xFFE3F1E7), Color(0xFFA9D8B6), Color(0xFF3E9A68), Color(0xFF0B5A3A), Color(0xFF06331F)];
  final x = t.clamp(0.0, 1.0) * (stops.length - 1);
  final i = x.floor().clamp(0, stops.length - 2);
  return Color.lerp(stops[i], stops[i + 1], x - i)!;
}

String _riders(double v) => v >= 10 ? Fmt.count(v.round()) : v.toStringAsFixed(v < 1 && v > 0 ? 1 : 0);

enum DemandMode { estimated, booked }

/// Demand by corridor (rows) and hour of day (columns).
class DemandHeatmap extends StatefulWidget {
  const DemandHeatmap({super.key, required this.report, this.limit = 8});
  final DemandReport report;
  final int limit;

  @override
  State<DemandHeatmap> createState() => _DemandHeatmapState();
}

class _DemandHeatmapState extends State<DemandHeatmap> {
  DemandMode _mode = DemandMode.estimated;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = widget.report;
    final rows = _all ? r.corridors : r.corridors.take(widget.limit).toList();
    double value(CorridorDemand c, int h) => _mode == DemandMode.estimated ? c.estimateByHour[h] : c.bookedByHour[h].toDouble();
    var peak = 0.0;
    (CorridorDemand, int)? hottest;
    for (final c in rows) {
      for (var h = _from; h <= _to; h++) {
        if (value(c, h) > peak) {
          peak = value(c, h);
          hottest = (c, h);
        }
      }
    }
    final subtitle = _mode == DemandMode.estimated
        ? 'Riders per hour on an average day: each corridor\'s 30-day trips spread over its timetable and weighted by when ${Fmt.count(r.bookingsUsed)} app bookings depart.'
        : 'Seats booked in the Tap A Ride app by departure hour, last ${r.windowDays} days and upcoming.';

    return DashPanel(
      title: 'Demand by corridor and hour',
      subtitle: subtitle,
      children: [
        if (!r.isEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: PillTabs<DemandMode>(values: DemandMode.values, labelOf: (m) => m == DemandMode.estimated ? 'Estimated riders' : 'App bookings', selected: _mode, onChanged: (m) => setState(() => _mode = m)),
          ),
          const SizedBox(height: 14),
        ],
        if (r.isEmpty)
          const EmptyState(icon: Icons.grid_on_rounded, title: 'No corridor demand yet', message: 'Demand appears here once routes are published and riders start booking.')
        else ...[
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 640;
            final labelW = narrow ? 92.0 : 230.0;
            const totalW = 64.0;
            const hours = _to - _from + 1;
            final fit = (c.maxWidth - labelW - totalW - 8) / hours;
            final cellW = math.max(fit, 20.0);
            final grid = SizedBox(
              width: labelW + totalW + 8 + cellW * hours,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  SizedBox(width: labelW, child: Text(narrow ? 'Route' : 'Corridor', style: text.labelSmall)),
                  for (var h = _from; h <= _to; h++)
                    SizedBox(width: cellW, child: Text(h % 3 == 0 ? h.toString().padLeft(2, '0') : '', textAlign: TextAlign.center, style: text.labelSmall?.copyWith(fontFeatures: tabular))),
                  const SizedBox(width: 8),
                  SizedBox(width: totalW, child: Text(_mode == DemandMode.estimated ? 'Per day' : 'Booked', textAlign: TextAlign.right, style: text.labelSmall)),
                ]),
                const SizedBox(height: 6),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(children: [
                      SizedBox(
                        width: labelW,
                        child: Row(children: [
                          _CodeTag(row.route.code),
                          if (!narrow) ...[const SizedBox(width: 8), Expanded(child: Text(row.route.title, style: text.bodySmall?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis))],
                        ]),
                      ),
                      for (var h = _from; h <= _to; h++)
                        Tooltip(
                          message: '${row.route.code} ${row.route.title}\n${hourLabel(h)}–${hourLabel(h + 1)} · ${row.departuresByHour[h]} departures\n'
                              '~${_riders(row.estimateByHour[h])} riders (est.) · ${row.bookedByHour[h]} booked in app',
                          child: Container(
                            width: cellW - 3,
                            height: 26,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              color: row.departuresByHour[h] == 0 && value(row, h) == 0 ? Colors.transparent : demandColor(peak == 0 ? 0 : value(row, h) / peak),
                              borderRadius: BorderRadius.circular(4),
                              border: hottest != null && hottest.$1 == row && hottest.$2 == h
                                  ? Border.all(color: AppLime.lime, width: 2.5)
                                  : (row.departuresByHour[h] == 0 ? Border.all(color: AppColors.line) : null),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: totalW,
                        child: Text(
                          _mode == DemandMode.estimated ? _riders(row.dailyTrips) : '${row.booked}',
                          textAlign: TextAlign.right,
                          style: text.labelMedium?.copyWith(fontFeatures: tabular),
                        ),
                      ),
                    ]),
                  ),
              ]),
            );
            return cellW > fit ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid) : grid;
          }),
          const SizedBox(height: 14),
          Wrap(spacing: 18, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Fewer', style: text.labelSmall),
              const SizedBox(width: 6),
              Container(
                width: 88,
                height: 8,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), gradient: LinearGradient(colors: [for (var i = 0; i <= 4; i++) demandColor(0.02 + i * 0.245)])),
              ),
              const SizedBox(width: 6),
              Text('More riders', style: text.labelSmall),
            ]),
            if (hottest != null && peak > 0)
              Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(width: 12, height: 12, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(border: Border.all(color: AppLime.lime, width: 2.5), borderRadius: BorderRadius.circular(3))),
                  ),
                  TextSpan(text: 'Busiest: ${hottest.$1.route.code} at ${hourLabel(hottest.$2)} · ${_mode == DemandMode.estimated ? '~${_riders(peak)} riders' : '${peak.round()} booked'}'),
                ]),
                style: text.labelMedium,
              ),
            if (r.corridors.length > widget.limit)
              TextButton(onPressed: () => setState(() => _all = !_all), child: Text(_all ? 'Show top ${widget.limit}' : 'Show all ${r.corridors.length} corridors')),
          ]),
        ],
      ],
    );
  }
}

class _CodeTag extends StatelessWidget {
  const _CodeTag(this.code);
  final String code;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 40),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(5)),
        child: Text(code, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.3, height: 1.2)),
      );
}

/// Riders (or bookings) by hour of day as columns, with the busiest hour highlighted.
class HourChart extends StatelessWidget {
  const HourChart({super.key, required this.values, this.secondary, this.unit = 'riders', this.secondaryUnit = 'booked in app', this.height = 168});
  final List<double> values;

  /// A second count per hour shown in tooltips (e.g. app bookings).
  final List<int>? secondary;
  final String unit;
  final String secondaryUnit;
  final double height;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final slice = values.sublist(_from, _to + 1);
    final peak = slice.fold<double>(0, math.max);
    if (peak == 0) return Text('Hours fill in as riders book.', style: text.bodyMedium);
    final peakHour = _from + slice.indexOf(peak);
    final summary = [for (var i = 0; i < slice.length; i++) '${_from + i}:00 ${_riders(slice[i])}'].join(', ');
    return Semantics(
      label: '$unit by hour: $summary',
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: height,
            child: Stack(children: [
              // Light gridlines at a quarter, half and three quarters of the peak.
              for (final f in [0.25, 0.5, 0.75, 1.0])
                Positioned(left: 0, right: 0, bottom: (height - 20) * f, child: Container(height: 1, color: AppColors.line.withValues(alpha: f == 1.0 ? 0.0 : 0.8))),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < slice.length; i++)
                  Expanded(
                    child: Tooltip(
                      message: '${hourLabel(_from + i)}–${hourLabel(_from + i + 1)}\n${_riders(slice[i])} $unit${secondary == null ? '' : ' · ${secondary![_from + i]} $secondaryUnit'}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          if (_from + i == peakHour)
                            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(Fmt.compact(slice[i].round()), maxLines: 1, overflow: TextOverflow.visible, softWrap: false, style: text.labelSmall?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800))),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: slice[i] / peak),
                            duration: Duration(milliseconds: 420 + i * 18),
                            curve: Curves.easeOutCubic,
                            builder: (context, t, _) => Container(
                              height: math.max(slice[i] > 0 ? 3 : 0, (height - 20) * t),
                              decoration: BoxDecoration(
                                color: _from + i == peakHour ? AppColors.forest : (slice[i] / peak > 0.6 ? const Color(0xFF3E9A68) : AppColors.mintStrong),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
          Container(height: 1, color: AppColors.lineStrong),
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 0; i < slice.length; i++)
              Expanded(child: Text((_from + i) % 3 == 0 ? '${(_from + i).toString().padLeft(2, '0')}:00' : '', maxLines: 1, softWrap: false, overflow: TextOverflow.visible, textAlign: TextAlign.center, style: text.labelSmall?.copyWith(fontSize: 11))),
          ]),
        ]),
      ),
    );
  }
}

/// When riders travel across every corridor in the scope.
class DemandByHourPanel extends StatelessWidget {
  const DemandByHourPanel({super.key, required this.report});
  final DemandReport report;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = report;
    return DashPanel(
      title: 'When riders travel',
      subtitle: r.isEmpty ? 'Bookings by departure hour' : 'Estimated riders per hour across ${r.corridors.length} corridors',
      children: [
        if (r.isEmpty)
          Text('Hours fill in as riders book.', style: text.bodyMedium)
        else ...[
          HourChart(values: r.estimateByHour, secondary: r.bookedByHour),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Fact(icon: Icons.schedule_rounded, label: 'Busiest hour', value: r.peakWindow),
            _Fact(icon: Icons.groups_rounded, label: 'Riders a day', value: Fmt.count(r.dailyTrips.round())),
            _Fact(icon: Icons.trending_up_rounded, label: 'In peak hours', value: '${(r.peakShare * 100).round()}%'),
            _Fact(icon: Icons.confirmation_number_outlined, label: 'App bookings', value: Fmt.count(r.booked)),
          ]),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: AppColors.surfaceSunk, borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: AppColors.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.forest),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: text.bodySmall?.copyWith(fontSize: 11.5, height: 1.2)),
          Text(value, style: text.labelLarge?.copyWith(fontFeatures: tabular, height: 1.2)),
        ]),
      ]),
    );
  }
}

/// The corridors ranked by riders, with when each one peaks.
class CorridorTable extends StatelessWidget {
  const CorridorTable({super.key, required this.report, this.limit = 10});
  final DemandReport report;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = report.corridors.take(limit).toList();
    final top = rows.isEmpty ? 1.0 : math.max(1.0, rows.map((c) => c.dailyTrips).reduce(math.max));
    return DataList<CorridorDemand>(
      items: rows,
      empty: const Panel(child: EmptyState(icon: Icons.alt_route_rounded, title: 'No corridors yet', message: 'Published routes appear here with their demand.')),
      titleOf: (c) => Row(children: [_CodeTag(c.route.code), const SizedBox(width: 8), Expanded(child: Text(c.route.title, overflow: TextOverflow.ellipsis))]),
      columns: [
        Col('Corridor', flex: 5, (c) => Row(children: [
              _CodeTag(c.route.code),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.route.title, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: c.dailyTrips / top, minHeight: 5, backgroundColor: AppColors.surfaceSunk, color: AppColors.forest),
                  ),
                ]),
              ),
            ])),
        Col('Riders / day', numeric: true, (c) => Text(_riders(c.dailyTrips), style: text.titleSmall?.copyWith(fontFeatures: tabular))),
        Col('Busiest hour', numeric: true, (c) => Text(hourLabel(c.peakHour), style: text.bodyMedium?.copyWith(fontFeatures: tabular))),
        Col('Per departure', numeric: true, (c) => Text('~${c.peakLoad.round()}', style: text.bodyMedium?.copyWith(fontFeatures: tabular, color: c.peakLoad > 60 ? AppColors.red : AppColors.inkSoft, fontWeight: c.peakLoad > 60 ? FontWeight.w700 : null))),
        Col('App bookings', numeric: true, (c) => Text('${c.booked}${c.bookedToday > 0 ? ' · ${c.bookedToday} today' : ''}', style: text.bodyMedium?.copyWith(fontFeatures: tabular))),
      ],
    );
  }
}

/// Origin → destination pairs riders booked most.
class TopTripsPanel extends StatelessWidget {
  const TopTripsPanel({super.key, required this.report});
  final DemandReport report;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final trips = report.topTrips;
    final top = trips.isEmpty ? 1 : math.max(1, trips.first.bookings);
    return DashPanel(
      title: 'Most-booked trips',
      subtitle: 'Origin to destination, app bookings in the last ${report.windowDays} days',
      children: [
        if (trips.isEmpty) Text('Trips appear here as riders book in the app.', style: text.bodyMedium),
        for (final t in trips)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: RouteStrip(origin: t.origin, destination: t.destination, dense: true)),
                const SizedBox(width: 12),
                Text('${t.bookings}', style: text.titleSmall?.copyWith(fontFeatures: tabular)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: t.bookings / top, minHeight: 5, backgroundColor: AppColors.surfaceSunk, color: const Color(0xFF3E9A68)),
              ),
            ]),
          ),
      ],
    );
  }
}

/// The complete demand view: heatmap, hourly curve, top trips and the corridor table.
class DemandSection extends StatelessWidget {
  const DemandSection({super.key, required this.report, this.title = 'Demand', this.showTable = true});
  final DemandReport report;
  final String title;
  final bool showTable;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionLabel(
          title,
          subtitle: report.isEmpty ? null : '${report.corridors.length} corridors · ${Fmt.count(report.dailyTrips.round())} riders a day · busiest ${report.peakWindow}',
          trailing: report.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () async {
                    final ok = await downloadCsv('taparide-demand-${report.scopeName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase()}.csv', report.toCsvRows());
                    if (context.mounted) showMessage(context, ok ? 'Demand table downloaded' : 'Download is available in the web app.', error: !ok);
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('CSV'),
                ),
        ),
        DemandHeatmap(report: report),
        const SizedBox(height: PortalSpace.gap),
        TwoUp(leftFlex: 3, rightFlex: 2, left: DemandByHourPanel(report: report), right: TopTripsPanel(report: report)),
        if (showTable && report.corridors.isNotEmpty) ...[
          const SizedBox(height: PortalSpace.gap),
          CorridorTable(report: report),
        ],
      ]);
}
