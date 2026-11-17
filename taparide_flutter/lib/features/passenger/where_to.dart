import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/places.dart';
import '../../shared/ticking.dart';
import '../../shared/ui.dart';
import 'rider_widgets.dart';

typedef Place = ({String name, LatLng point});

/// "From your location → where to?" with place suggestions as you type
/// (known places, route stops, then the address search).
class WhereToCard extends StatefulWidget {
  const WhereToCard({super.key});

  @override
  State<WhereToCard> createState() => _WhereToCardState();
}

class _WhereToCardState extends State<WhereToCard> {
  final _to = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<Place> _remote = const [];
  int _searchId = 0;

  /// Suggestions stay open until a place is picked or the field is cleared
  /// (not tied to focus, which a tap on a suggestion takes away first).
  bool _open = false;

  @override
  void initState() {
    super.initState();
    if (LiveTicking.enabled) WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().locate());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _to.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String v) {
    setState(() => _open = v.trim().isNotEmpty);
    _debounce?.cancel();
    if (v.trim().length < 3) {
      setState(() => _remote = const []);
      return;
    }
    final id = ++_searchId;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final found = await context.read<AppState>().api.geocode('${v.trim()} Abuja');
      if (mounted && id == _searchId) setState(() => _remote = [for (final f in found) if (inFct(f.point)) f]);
    });
  }

  void _pick(Place to) {
    final state = context.read<AppState>();
    _focus.unfocus();
    setState(() => _open = false);
    _to.text = to.name;
    final from = state.here != null && inFct(state.here!) ? (name: state.hereName ?? 'Your location', point: state.here!) : null;
    showTripOptions(context, from: from, to: to);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final located = state.here != null && inFct(state.here!);
    final q = _to.text.trim();
    final local = suggestPlaces(q, routes: state.bookableRoutes);
    final names = {for (final p in local) p.name.toLowerCase()};
    final suggestions = [...local, for (final r in _remote) if (!names.contains(r.name.toLowerCase())) r].take(7).toList();

    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(located ? Icons.my_location_rounded : Icons.location_searching_rounded, size: 20, color: located ? const Color(0xFF2B6EF2) : AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              located
                  ? 'From: near ${state.hereName ?? 'you'}'
                  : state.locating
                      ? 'Finding your location…'
                      : state.here != null
                          ? 'You seem to be outside Abuja'
                          : 'From: allow location for pickups near you',
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.inkSoft),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!located && !state.locating)
            TextButton(onPressed: () => state.locate(force: true), child: const Text('Locate me'))
          else if (state.locating)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const Padding(padding: EdgeInsets.only(left: 9), child: SizedBox(height: 10, child: VerticalDivider(width: 2, thickness: 2, color: AppColors.line))),
        TextField(
          controller: _to,
          focusNode: _focus,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            if (suggestions.isNotEmpty) {
              _pick(suggestions.first);
            } else if (v.trim().isNotEmpty) {
              context.go(Uri(path: '/app/routes', queryParameters: {'q': v.trim()}).toString());
            }
          },
          decoration: InputDecoration(
            hintText: 'Where to? Try Gwarinpa, Jabi Lake Mall…',
            prefixIcon: const Icon(Icons.place_rounded, color: AppColors.forest),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _to.clear();
                      _remote = const [];
                      _open = false;
                    }),
                  ),
            isDense: true,
          ),
        ),
        if (_open && q.isNotEmpty) ...[
          const SizedBox(height: 6),
          if (suggestions.isEmpty)
            Padding(padding: const EdgeInsets.all(8), child: Text('Searching places…', style: text.bodySmall))
          else
            for (final s in suggestions)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.place_outlined, color: AppColors.muted),
                title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: located ? Text('${straightKm(state.here!, s.point).toStringAsFixed(1)} km away') : null,
                onTap: () => _pick(s),
              ),
        ],
      ]),
    );
  }
}

/// A bus route that serves the trip, with the walk at each end.
class _RouteMatch {
  const _RouteMatch(this.route, this.board, this.alight, this.walkKm);
  final TransitRoute route;
  final RouteStop board;
  final RouteStop alight;
  final double walkKm;
}

List<_RouteMatch> _matchRoutes(List<TransitRoute> routes, LatLng from, LatLng to) {
  final out = <_RouteMatch>[];
  for (final r in routes) {
    RouteStop? nearest(LatLng p) {
      RouteStop? best;
      var d = double.infinity;
      for (final s in r.stops) {
        final k = straightKm(p, LatLng(s.lat, s.lng));
        if (k < d) {
          d = k;
          best = s;
        }
      }
      return d <= 3 ? best : null;
    }

    final a = nearest(from), b = nearest(to);
    if (a == null || b == null || a.name == b.name) continue;
    out.add(_RouteMatch(r, a, b, straightKm(from, LatLng(a.lat, a.lng)) + straightKm(to, LatLng(b.lat, b.lng))));
  }
  out.sort((x, y) => x.walkKm.compareTo(y.walkKm));
  return out;
}

/// Ways to make a trip: buses that serve it, and a door-to-door electric car.
Future<void> showTripOptions(BuildContext context, {required Place? from, required Place to}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final state = context.read<AppState>();
      final text = Theme.of(sheet).textTheme;
      final origin = from ?? (name: 'Central Area', point: abujaCentre);
      final matches = _matchRoutes(state.bookableRoutes, origin.point, to.point).take(4).toList();
      final km = straightKm(origin.point, to.point) * 1.3;
      final evs = state.availableEvs.where((v) => v.status == VehicleStatus.active).toList();
      final ev = evs.isEmpty ? null : evs.first;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text('To ${to.name}', style: text.headlineSmall),
            Text('From ${from == null ? 'Central Area (location off)' : 'near ${origin.name}'} · about ${km.toStringAsFixed(1)} km by road', style: text.bodySmall),
            const SizedBox(height: 16),
            SectionHeader(title: 'Buses', subtitle: matches.isEmpty ? 'No fixed route goes this way yet' : 'Fixed fares, published times'),
            for (final m in matches)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  RouteRow(
                    route: m.route,
                    providerName: state.providerById(m.route.providerId)?.name,
                    onTap: () {
                      Navigator.pop(sheet);
                      context.push('/ride/${m.route.id}');
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Text(
                      'Board at ${m.board.name}, get off at ${m.alight.name} · ${max(1, (m.walkKm * 12).round())} min walking in total',
                      style: text.bodySmall,
                    ),
                  ),
                ]),
              ),
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Try an electric car below, or browse all routes.', style: text.bodyMedium),
              ),
            const SizedBox(height: 8),
            const SectionHeader(title: 'Door to door'),
            Panel(
              onTap: () {
                Navigator.pop(sheet);
                context.push('/ev');
              },
              child: Row(children: [
                const IconBadge(Icons.electric_car_rounded, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ev == null ? 'Electric car' : '${ev.model} · electric', style: text.titleMedium),
                    Text(ev == null ? 'None free right now' : 'Pickup in about ${carEta(ev, origin.name)} min · ${Fmt.minutes(max(5, (km * 2.4).round()))} ride', style: text.bodySmall),
                  ]),
                ),
                if (ev != null) Text(Fmt.naira(carFare(ev, km)), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheet);
                    context.push('/live');
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: const Text('Live map'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheet);
                    context.go(Uri(path: '/app/routes', queryParameters: {'q': to.name}).toString());
                  },
                  icon: const Icon(Icons.alt_route_rounded, size: 18),
                  label: const Text('All routes'),
                ),
              ),
            ]),
          ],
        ),
      );
    },
  );
}
