import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../brand.dart';

/// Non-web fallback: the logo pin, which hops once when it appears or its mood changes
/// (no endless looping motion, and none at all with reduced motion).
Widget buildMascot(String mood, double size) => _PinMascot(mood: mood, size: size);

class _PinMascot extends StatefulWidget {
  const _PinMascot({required this.mood, required this.size});
  final String mood;
  final double size;

  @override
  State<_PinMascot> createState() => _PinMascotState();
}

class _PinMascotState extends State<_PinMascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  @override
  void didUpdateWidget(covariant _PinMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final height = widget.mood == 'celebrate' ? 14.0 : 7.0;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, still ? 0 : -height * math.sin(math.pi * Curves.easeOut.transform(_c.value))),
        child: child,
      ),
      child: Center(child: Image.asset(BrandAssets.mark, width: widget.size * 0.9)),
    );
  }
}
