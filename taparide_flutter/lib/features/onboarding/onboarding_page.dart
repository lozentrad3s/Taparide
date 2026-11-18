import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/brand.dart';

/// First screens of the rider app: three full-bleed photo pages, then sign up or log in.
/// Shown once per device; afterwards the app opens on sign-in.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.query = const {}});

  /// Passed through to sign-up (e.g. `email` and `ref` from the website).
  final Map<String, String> query;

  static const seenKey = 'onboarding_seen_v1';

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _Slide {
  const _Slide(this.image, this.title, this.body, this.alignment);
  final String image;
  final String title;
  final String body;
  final Alignment alignment;
}

const _slides = [
  _Slide('assets/onboarding/move.jpg', 'Move more.\nWorry less.', 'Bus rides, event rides and shared trips across Abuja, with fixed fares and verified drivers.', Alignment(0, -0.4)),
  _Slide('assets/onboarding/together.jpg', 'Ride together,\npay less.', 'Book a seat on a bus or hop on a Tagalong ride with people heading your way. Share the trip live with family.', Alignment(0, -0.5)),
  _Slide('assets/onboarding/tap.jpg', 'Tap. Pay.\nYou’re on your way.', 'Top up once, then pay for every seat with a tap or a QR code. No change wahala, instant confirmation.', Alignment(0, -0.6)),
];

const _lime = Color(0xFF8CE01F);
const _ink = Color(0xFF0D1A12);

class _OnboardingPageState extends State<OnboardingPage> {
  final _pages = PageController();
  int _index = 0;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _skipIfSeen();
  }

  Future<void> _skipIfSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(OnboardingPage.seenKey) ?? false;
    if (!mounted) return;
    // Coming from the website with an email means "sign me up": go straight there.
    if (seen || widget.query.containsKey('email')) {
      _leave(widget.query.containsKey('email') ? '/register' : '/login');
      return;
    }
    setState(() => _checked = true);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _leave(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingPage.seenKey, true);
    if (!mounted) return;
    context.go(Uri(path: path, queryParameters: widget.query.isEmpty ? null : widget.query).toString());
  }

  void _next() {
    if (_index == _slides.length - 1) {
      _leave('/register');
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const Scaffold(backgroundColor: _ink);
    final text = Theme.of(context).textTheme;
    final pad = MediaQuery.paddingOf(context);
    final last = _index == _slides.length - 1;
    return Scaffold(
      backgroundColor: _ink,
      body: Stack(fit: StackFit.expand, children: [
        PageView.builder(
          controller: _pages,
          itemCount: _slides.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => _Photo(slide: _slides[i]),
        ),
        // Brand and log-in along the top.
        Positioned(
          left: 20,
          right: 12,
          top: pad.top + 12,
          child: Row(children: [
            const BrandLockup(height: 30, onDark: true),
            const Spacer(),
            TextButton(
              onPressed: () => _leave('/login'),
              style: TextButton.styleFrom(foregroundColor: Colors.white, textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              child: const Text('Log in'),
            ),
          ]),
        ),
        // Words, progress and the action at the bottom.
        Align(
          alignment: Alignment.bottomLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, pad.bottom + 28),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a), child: child),
                  ),
                  child: Column(
                    key: ValueKey(_index),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _slides[_index].title,
                        style: text.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.02, letterSpacing: -1),
                      ),
                      const SizedBox(height: 14),
                      Text(_slides[_index].body, style: text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.88), height: 1.45)),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Row(children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(right: 6),
                      height: 6,
                      width: i == _index ? 26 : 6,
                      decoration: BoxDecoration(color: i == _index ? _lime : Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)),
                    ),
                ]),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: _lime,
                      foregroundColor: _ink,
                      minimumSize: const Size.fromHeight(56),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                    ),
                    child: Text(last ? 'Create account' : 'Next'),
                  ),
                ),
                if (last) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => _leave('/login'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('I already have an account'),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Image.asset(slide.image, fit: BoxFit.cover, alignment: slide.alignment, excludeFromSemantics: true),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x88000000), Color(0x00000000), Color(0x22000000), Color(0xE6000000)],
            stops: [0, 0.22, 0.45, 0.82],
          ),
        ),
      ),
    ]);
  }
}
