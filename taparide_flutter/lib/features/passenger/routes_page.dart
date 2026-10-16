import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';
import 'rider_widgets.dart';

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  State<RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends State<RoutesPage> {
  late final _query = TextEditingController(text: widget.initialQuery ?? '');
  TransitMode? _mode;

  @override
  void didUpdateWidget(covariant RoutesPage old) {
    super.didUpdateWidget(old);
    if (widget.initialQuery != old.initialQuery && widget.initialQuery != null) _query.text = widget.initialQuery!;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(TransitRoute r, String q) {
    if (q.isEmpty) return true;
    final haystack = [r.code, r.name ?? '', for (final s in r.stops) s.name].join(' ').toLowerCase();
    return q.toLowerCase().split(RegExp(r'\s+')).every(haystack.contains);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final wide = isWide(context, 900);
    final q = _query.text.trim();
    final results = [
      for (final r in state.bookableRoutes)
        if ((_mode == null || r.mode == _mode) && _matches(r, q)) r
    ];

    return Scaffold(
      body: SafeArea(
        child: DataGate(
          builder: (context) => CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: MaxWidth(
                width: 900,
                padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 18, wide ? 32 : 18, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Routes', style: text.headlineLarge),
                  const SizedBox(height: 4),
                  Text('Fixed fares and published departures from verified operators.', style: text.bodyMedium),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search a stop or area, e.g. Gwarinpa',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.forest),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(_query.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(spacing: 8, children: [
                      for (final option in <TransitMode?>[null, ...TransitMode.values])
                        ChoiceChip(
                          label: Text(option?.label ?? 'All'),
                          avatar: option == null ? null : Icon(option.icon, size: 16, color: _mode == option ? Colors.white : AppColors.forest),
                          selected: _mode == option,
                          showCheckmark: false,
                          labelStyle: TextStyle(color: _mode == option ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
                          onSelected: (_) => setState(() => _mode = option),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Text('${results.length} ${results.length == 1 ? 'route' : 'routes'}', style: text.labelMedium?.copyWith(color: AppColors.muted)),
                ]),
              ),
            ),
            if (results.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.alt_route_rounded,
                  title: 'No routes match "$q"',
                  message: 'Try a nearby area or stop name. New routes appear here as operators are verified.',
                  action: 'Show all routes',
                  onAction: () => setState(() {
                    _query.clear();
                    _mode = null;
                  }),
                ),
              )
            else
              SliverList.builder(
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final r = results[i];
                  return MaxWidth(
                    width: 900,
                    padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 0, wide ? 32 : 18, 10),
                    child: RouteRow(route: r, providerName: state.providerById(r.providerId)?.name, onTap: () => context.push('/ride/${r.id}')),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        ),
      ),
    );
  }
}
