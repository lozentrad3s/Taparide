import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/photos.dart';
import '../../shared/brand.dart';
import '../../shared/ui.dart';

/// Public "Get Started" page, following the laptop screen in the client mockup.
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scroll = ScrollController();
  final _routesKey = GlobalKey();
  final _operatorsKey = GlobalKey();
  final _governmentKey = GlobalKey();
  final _aboutKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    context.read<AppState>().loadPublicRoutes();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jump(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic, alignment: 0.04);
  }

  void _start() {
    final user = context.read<AppState>().user;
    context.go(user == null ? '/register' : homeFor(user));
  }

  void _openRoute(TransitRoute route) {
    final user = context.read<AppState>().user;
    if (user != null && !user.role.isPartner) {
      context.push('/ride/${route.id}');
    } else {
      context.go(Uri(path: '/login', queryParameters: {'from': '/ride/${route.id}'}).toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context, 980);
    final routes = context.watch<AppState>().publicRoutes;
    final nav = _NavLinks(
      onHome: () => _scroll.animateTo(0, duration: const Duration(milliseconds: 480), curve: Curves.easeOutCubic),
      onRoutes: () => _jump(_routesKey),
      onOperators: () => _jump(_operatorsKey),
      onGovernment: () => _jump(_governmentKey),
      onAbout: () => _jump(_aboutKey),
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(child: _TopBar(wide: wide, links: nav, onStart: _start)),
            SliverToBoxAdapter(child: _Hero(wide: wide, routes: routes, onStart: _start)),
            const SliverToBoxAdapter(child: _FeatureStrip()),
            SliverToBoxAdapter(child: KeyedSubtree(key: _routesKey, child: _HowItWorks(wide: wide, routes: routes, onRoute: _openRoute))),
            SliverToBoxAdapter(child: KeyedSubtree(key: _operatorsKey, child: _EveryoneConnected(wide: wide))),
            SliverToBoxAdapter(child: _EvAndTagAlong(wide: wide)),
            SliverToBoxAdapter(child: KeyedSubtree(key: _governmentKey, child: _ForPartners(wide: wide))),
            SliverToBoxAdapter(child: KeyedSubtree(key: _aboutKey, child: _Closing(wide: wide, onStart: _start))),
          ],
        ),
      ),
    );
  }
}

class _NavLinks {
  const _NavLinks({required this.onHome, required this.onRoutes, required this.onOperators, required this.onGovernment, required this.onAbout});
  final VoidCallback onHome;
  final VoidCallback onRoutes;
  final VoidCallback onOperators;
  final VoidCallback onGovernment;
  final VoidCallback onAbout;

  List<(String, VoidCallback)> get items => [
        ('Home', onHome),
        ('Routes', onRoutes),
        ('For Operators', onOperators),
        ('For Government', onGovernment),
        ('About', onAbout),
      ];
}

// ------------------------------------------------------------------ top bar

class _TopBar extends StatelessWidget {
  const _TopBar({required this.wide, required this.links, required this.onStart});
  final bool wide;
  final _NavLinks links;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().user;
    final text = Theme.of(context).textTheme;
    return MaxWidth(
      width: 1240,
      padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(fit: BoxFit.scaleDown, child: BrandLockup(height: wide ? 40 : 32, showDescriptor: true)),
            ),
          ),
          const SizedBox(width: 12),
          if (wide) ...[
            for (final (label, action) in links.items)
              TextButton(
                key: ValueKey('nav-$label'),
                onPressed: action,
                style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft, textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                child: Text(label),
              ),
            const SizedBox(width: 12),
            if (user == null) TextButton(onPressed: () => context.go('/login'), child: const Text('Log in')),
            const SizedBox(width: 6),
            FilledButton(onPressed: onStart, child: Text(user == null ? 'Get Started' : 'Open my dashboard')),
          ] else ...[
            if (user == null) TextButton(key: const ValueKey('login-compact'), onPressed: () => context.go('/login'), child: const Text('Log in')),
            IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (sheet) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final (label, action) in links.items)
                        ListTile(
                          title: Text(label, style: text.titleMedium),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.pop(sheet);
                            Future.delayed(const Duration(milliseconds: 220), action);
                          },
                        ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(sheet);
                          onStart();
                        },
                        child: Text(user == null ? 'Get Started' : 'Open my dashboard'),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ hero

class _Hero extends StatefulWidget {
  const _Hero({required this.wide, required this.routes, required this.onStart});
  final bool wide;
  final List<TransitRoute> routes;
  final VoidCallback onStart;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
    } else if (!_intro.isAnimating && _intro.value == 0) {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Widget _rise(double start, Widget child) {
    final curve = CurvedAnimation(parent: _intro, curve: Interval(start, (start + 0.55).clamp(0, 1), curve: Curves.easeOutExpo));
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(offset: Offset(0, 28 * (1 - curve.value)), child: child),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final wide = widget.wide;
    final headline = Text(
      'Smarter Transport.\nA Better Abuja.',
      style: (wide ? text.displayLarge : text.displayMedium)?.copyWith(color: AppColors.ink),
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rise(0, headline),
        const SizedBox(height: 18),
        _rise(
          0.12,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              'Book, pay and ride with ease. Tap A Ride connects riders, operators, fleet owners and government — all in one place.',
              style: text.bodyLarge?.copyWith(fontSize: wide ? 19 : 17),
            ),
          ),
        ),
        const SizedBox(height: 26),
        _rise(
          0.22,
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(
              onPressed: widget.onStart,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              label: const Text('Get Started'),
              style: FilledButton.styleFrom(minimumSize: const Size(170, 56), textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            OutlinedButton(
              onPressed: () => context.go('/login?portal=partner'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(150, 56)),
              child: const Text('Partner portal'),
            ),
          ]),
        ),
      ],
    );

    final featured = widget.routes.where((r) => r.mode == TransitMode.rail).firstOrNull ?? widget.routes.firstOrNull;
    final visual = _rise(0.08, _HeroVisual(wide: wide, route: featured));

    return MaxWidth(
      width: 1240,
      padding: EdgeInsets.fromLTRB(wide ? 32 : 18, wide ? 28 : 12, wide ? 32 : 18, wide ? 44 : 28),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 10, child: copy),
                const SizedBox(width: 40),
                Expanded(flex: 13, child: visual),
              ],
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [copy, const SizedBox(height: 28), visual]),
    );
  }
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual({required this.wide, required this.route});
  final bool wide;
  final TransitRoute? route;

  @override
  Widget build(BuildContext context) {
    final height = wide ? 540.0 : 340.0;
    return SizedBox(
      height: height + (wide ? 0 : 70),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: height,
            child: PhotoView(
              AppPhoto.lightRail,
              radius: 28,
              alignment: const Alignment(0.35, 0),
              semanticLabel: 'An Abuja light-rail train waiting at a station platform',
              overlay: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.55, 1],
                colors: [Color(0x00000000), Color(0x5506331F)],
              ),
            ),
          ),
          Positioned(
            left: wide ? -36 : 14,
            right: wide ? null : 14,
            bottom: wide ? 36 : 0,
            child: _DepartureCard(route: route, width: wide ? 372 : null),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(999), boxShadow: AppShadow.card),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_rounded, size: 16, color: AppColors.forest),
                SizedBox(width: 6),
                Text('Every vehicle verified', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rider's next departure, as it appears in the app (demonstration of the product).
class _DepartureCard extends StatelessWidget {
  const _DepartureCard({required this.route, this.width});
  final TransitRoute? route;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = route;
    final next = r?.upcomingDepartures(DateTime.now(), count: 1).firstOrNull;
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.xl), boxShadow: AppShadow.raised),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            IconBadge(r?.mode.icon ?? Icons.directions_bus_rounded, size: 36, radius: 10),
            const SizedBox(width: 10),
            Expanded(child: Text(r?.name == null ? 'Next departure' : 'Next ${r!.name}', style: text.labelMedium?.copyWith(color: AppColors.muted))),
            Text(next == null ? '—' : Fmt.time(next), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular)),
          ]),
          const SizedBox(height: 14),
          RouteStrip(origin: r?.origin ?? 'Wuse', destination: r?.destination ?? 'Maitama', stops: r?.stops.length ?? 3),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Fixed fare', style: text.labelSmall),
                const SizedBox(height: 2),
                Text(Fmt.naira(r?.fare ?? 500), style: text.titleLarge?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.contactless_rounded, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text('Tap to pay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ feature strip

class _FeatureStrip extends StatelessWidget {
  const _FeatureStrip();

  static const _items = [
    (Icons.contactless_outlined, 'Book & pay with a tap card or QR code'),
    (Icons.verified_user_outlined, 'Safe & verified vehicles'),
    (Icons.schedule_rounded, 'Real-time routes & schedules'),
    (Icons.insights_rounded, 'Transparent revenue for operators & owners'),
    (Icons.account_balance_outlined, 'Data for a smarter FCT'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context, 980);
    final text = Theme.of(context).textTheme;
    Widget item((IconData, String) entry) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(entry.$1, color: AppColors.forest, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(entry.$2, style: text.titleSmall?.copyWith(height: 1.3))),
          ],
        );
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.ground,
        border: Border.symmetric(horizontal: BorderSide(color: AppColors.line)),
      ),
      child: MaxWidth(
        width: 1240,
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18, vertical: 26),
        child: wide
            ? IntrinsicHeight(
                child: Row(children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0) const VerticalDivider(width: 36, color: AppColors.lineStrong),
                    Expanded(child: item(_items[i])),
                  ],
                ]),
              )
            : Wrap(
                runSpacing: 18,
                children: [for (final e in _items) FractionallySizedBox(widthFactor: MediaQuery.sizeOf(context).width > 560 ? 0.5 : 1, child: Padding(padding: const EdgeInsets.only(right: 12), child: item(e)))],
              ),
      ),
    );
  }
}

// ------------------------------------------------------------------ how it works

class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.wide, required this.routes, required this.onRoute});
  final bool wide;
  final List<TransitRoute> routes;
  final ValueChanged<TransitRoute> onRoute;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shown = routes.take(3).toList();
    final steps = [
      _Step(
        title: 'Choose a fixed-fare route',
        body: 'See the fare and journey time before you go. No haggling, no surprises when it rains.',
        child: Column(children: [
          for (final r in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shadow: false,
                onTap: () => onRoute(r),
                semanticLabel: '${r.title}, ${Fmt.naira(r.fare)}',
                child: Row(children: [
                  Expanded(child: RouteStrip(origin: r.name ?? r.origin, destination: r.name == null ? r.destination : r.mode.label, stops: r.stops.length, dense: true)),
                  const SizedBox(width: 8),
                  Text(Fmt.naira(r.fare), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
                ]),
              ),
            ),
          if (shown.isEmpty) const SizedBox(height: 120),
        ]),
      ),
      _Step(
        title: 'Pick your departure',
        body: 'Every route runs to a published timetable. Book a seat on the one that suits you.',
        child: Builder(builder: (context) {
          final times = (shown.isEmpty ? null : shown.first)?.upcomingDepartures(DateTime.now(), count: 4) ?? const <DateTime>[];
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < times.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: i == 1 ? AppColors.forest : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: i == 1 ? AppColors.forest : AppColors.lineStrong),
                ),
                child: Text(Fmt.time(times[i]), style: text.labelLarge?.copyWith(color: i == 1 ? Colors.white : AppColors.ink, fontFeatures: tabular)),
              ),
          ]);
        }),
      ),
      _Step(
        title: 'Tap your card or show your QR',
        body: 'Pay from your tap card balance at the terminal, or let the conductor scan your ticket.',
        child: Row(children: [
          Expanded(
            child: Container(
              height: 104,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                gradient: const LinearGradient(colors: [AppColors.forest, AppColors.forestDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Tap Card', style: text.titleMedium?.copyWith(color: Colors.white)),
                  const Spacer(),
                  const Icon(Icons.contactless_rounded, color: Colors.white),
                ]),
                const Spacer(),
                Text('Balance', style: text.labelSmall?.copyWith(color: AppColors.onForestMuted)),
                Text(Fmt.naira(2500), style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.line)),
            child: const Icon(Icons.qr_code_2_rounded, size: 72, color: AppColors.ink),
          ),
        ]),
      ),
    ];

    return MaxWidth(
      width: 1240,
      padding: EdgeInsets.fromLTRB(wide ? 32 : 18, wide ? 88 : 56, wide ? 32 : 18, wide ? 40 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From tap to seat in three steps', style: (wide ? text.displaySmall : text.headlineLarge)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text('Fixed fares, published departures and cashless payment on routes across the FCT, from Kubwa and Nyanya to Maitama and the Central Area.', style: text.bodyLarge),
          ),
          const SizedBox(height: 34),
          if (wide)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 20),
                  Expanded(child: _StepView(index: i + 1, step: steps[i])),
                ],
              ]),
            )
          else
            Column(children: [
              for (var i = 0; i < steps.length; i++) Padding(padding: const EdgeInsets.only(bottom: 16), child: _StepView(index: i + 1, step: steps[i])),
            ]),
        ],
      ),
    );
  }
}

class _Step {
  const _Step({required this.title, required this.body, required this.child});
  final String title;
  final String body;
  final Widget child;
}

class _StepView extends StatelessWidget {
  const _StepView({required this.index, required this.step});
  final int index;
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.forest, shape: BoxShape.circle),
              child: Text('$index', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(step.title, style: text.titleLarge)),
          ]),
          const SizedBox(height: 10),
          Text(step.body, style: text.bodyMedium),
          const SizedBox(height: 18),
          step.child,
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ everyone connected

class _EveryoneConnected extends StatelessWidget {
  const _EveryoneConnected({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final roles = [
      (Icons.person_rounded, 'Riders', 'Book, pay and ride with ease.', 'Ride now', '/login'),
      (Icons.directions_bus_rounded, 'Operators', 'Manage routes, fares and schedules.', 'Operator sign-in', '/login?portal=partner'),
      (Icons.local_shipping_rounded, 'Fleet owners', 'Track revenue and performance per vehicle.', 'Owner sign-in', '/login?portal=partner'),
      (Icons.account_balance_rounded, 'Government', 'Access data for a safer, smarter FCT.', 'FCTA sign-in', '/login?portal=partner'),
    ];
    final tiles = [
      for (final role in roles)
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => context.go(role.$5),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconBadge(role.$1, size: 48, color: AppColors.forest, iconColor: Colors.white, radius: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(role.$2, style: text.titleLarge),
                    const SizedBox(height: 4),
                    Text(role.$3, style: text.bodyMedium),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text(role.$4, style: text.labelLarge?.copyWith(color: AppColors.forest)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.forest),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
    ];

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrandLogo(width: wide ? 250 : 200, onDark: true),
        const SizedBox(height: 26),
        Text('One Platform.\nEveryone Connected.', style: (wide ? text.displaySmall : text.headlineLarge)?.copyWith(color: Colors.white)),
        const SizedBox(height: 14),
        Text(
          'Abuja has the terminals and the buses. Tap A Ride is the system that runs them: every trip, every naira and every verified vehicle in one place.',
          style: text.bodyLarge?.copyWith(color: AppColors.onForestMuted),
        ),
      ],
    );

    return Container(
      color: AppColors.forest,
      margin: EdgeInsets.only(top: wide ? 48 : 24),
      child: MaxWidth(
        width: 1240,
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18, vertical: wide ? 84 : 52),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(flex: 9, child: intro),
                const SizedBox(width: 56),
                Expanded(
                  flex: 13,
                  child: Column(children: [
                    IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: tiles[0]), const SizedBox(width: 14), Expanded(child: tiles[1])])),
                    const SizedBox(height: 14),
                    IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: tiles[2]), const SizedBox(width: 14), Expanded(child: tiles[3])])),
                  ]),
                ),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                intro,
                const SizedBox(height: 28),
                for (final tile in tiles) Padding(padding: const EdgeInsets.only(bottom: 12), child: tile),
              ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ EVs + Tag Along

class _EvAndTagAlong extends StatelessWidget {
  const _EvAndTagAlong({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final ev = _PhotoFeature(
      photo: AppPhoto.evCharging,
      alt: 'A white electric SUV',
      title: 'Book an electric ride',
      body: 'Quiet, zero-emission cars from verified EV operators, with the battery level and pickup time shown before you book.',
      bullets: const ['Live battery and range', 'Fare shown up front', 'Verified drivers'],
      action: 'Book an EV',
      route: '/ev',
    );
    final tag = _PhotoFeature(
      photo: AppPhoto.taxis,
      alt: 'Green and white Abuja taxis on the road',
      title: 'Tag Along: share rides, save more',
      body: 'Verified professionals share the ride home with colleagues who live in the same area, and split the cost.',
      bullets: const ['Verified users only', 'Safe & convenient', 'Split cost, save more'],
      action: 'Find a ride',
      route: '/tag-along',
    );
    return MaxWidth(
      width: 1240,
      padding: EdgeInsets.fromLTRB(wide ? 32 : 18, wide ? 88 : 52, wide ? 32 : 18, 0),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: ev), const SizedBox(width: 24), Expanded(child: tag)])
          : Column(children: [ev, const SizedBox(height: 28), tag]),
    );
  }
}

class _PhotoFeature extends StatelessWidget {
  const _PhotoFeature({required this.photo, required this.alt, required this.title, required this.body, required this.bullets, required this.action, required this.route});
  final AppPhoto photo;
  final String alt;
  final String title;
  final String body;
  final List<String> bullets;
  final String action;
  final String route;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(aspectRatio: 16 / 10, child: PhotoView(photo, radius: AppRadius.xl, semanticLabel: alt)),
        const SizedBox(height: 20),
        Text(title, style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(body, style: text.bodyLarge),
        const SizedBox(height: 14),
        for (final b in bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.leaf, size: 20),
              const SizedBox(width: 10),
              Text(b, style: text.titleSmall),
            ]),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            final user = context.read<AppState>().user;
            context.go(user == null ? Uri(path: '/login', queryParameters: {'from': route}).toString() : route);
          },
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: Text(action),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ partners

class _ForPartners extends StatelessWidget {
  const _ForPartners({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final columns = [
      (Icons.directions_bus_rounded, 'Transport operators', ['Routes, fares and timetables', 'AI income and demand analysis', 'Live traffic vs timetable']),
      (Icons.local_shipping_rounded, 'Fleet owners & private drivers', ['What every vehicle earns', 'Idle-vehicle cost, worked out for you', 'Register with licence, plate and chassis']),
      (Icons.account_balance_rounded, 'Government / FCTA', ['Ridership and demand hot-spots across the FCT', 'AI-checked partner applications', 'Verified-vehicle register and audit trail']),
    ];
    return MaxWidth(
      width: 1240,
      padding: EdgeInsets.fromLTRB(wide ? 32 : 18, wide ? 96 : 56, wide ? 32 : 18, wide ? 96 : 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Run transport on facts', style: wide ? text.displaySmall : text.headlineLarge),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text('Every booking made in the rider app shows up in the operator, fleet-owner and FCTA dashboards. Each partner sees exactly what their role allows.', style: text.bodyLarge),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 24,
            runSpacing: 28,
            children: [
              for (final c in columns)
                SizedBox(
                  width: wide ? (1240 - 64 - 48) / 3 : double.infinity,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(c.$1, color: AppColors.forest, size: 26),
                      const SizedBox(width: 10),
                      Text(c.$2, style: text.titleLarge),
                    ]),
                    const SizedBox(height: 12),
                    const Divider(),
                    for (final line in c.$3)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.forest, width: 2.5)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(line, style: text.bodyMedium?.copyWith(color: AppColors.ink))),
                        ]),
                      ),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(onPressed: () => context.go('/partner/apply'), icon: const Icon(Icons.handshake_rounded, size: 18), label: const Text('Become a partner')),
            OutlinedButton(onPressed: () => context.go('/login?portal=partner'), child: const Text('Partner sign-in')),
          ]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ closing

class _Closing extends StatelessWidget {
  const _Closing({required this.wide, required this.onStart});
  final bool wide;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        SizedBox(
          height: wide ? 480 : 420,
          width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            const PhotoView(
              AppPhoto.cityGateAerial,
              alignment: Alignment(0, 0.1),
              semanticLabel: 'Abuja City Gate with green lawns and flags on the airport road',
              overlay: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x1106331F), Color(0xDD06331F)]),
            ),
            MaxWidth(
              width: 1240,
              padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18, vertical: 44),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Energising smart mobility\nfor a greater Abuja.', style: (wide ? text.displayMedium : text.headlineLarge)?.copyWith(color: Colors.white)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onStart,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Get Started'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.forest, minimumSize: const Size(170, 56)),
                  ),
                ],
              ),
            ),
          ]),
        ),
        Container(
          color: AppColors.forestDeep,
          child: MaxWidth(
            width: 1240,
            padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18, vertical: 26),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 14,
              spacing: 20,
              children: [
                const BrandLockup(height: 28, onDark: true),
                Text('Built for ATDEW 2026 · Abuja, FCT', style: text.bodySmall?.copyWith(color: AppColors.onForestMuted)),
                Wrap(spacing: 4, children: [
                  TextButton(onPressed: () => context.go('/credits'), style: TextButton.styleFrom(foregroundColor: Colors.white), child: const Text('Photo credits')),
                  TextButton(onPressed: () => context.go('/login?portal=partner'), style: TextButton.styleFrom(foregroundColor: Colors.white), child: const Text('Partner portal')),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
