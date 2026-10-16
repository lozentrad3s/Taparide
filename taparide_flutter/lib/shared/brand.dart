import 'package:flutter/material.dart';

/// Tap A Ride artwork supplied by the client (cut from the original logo file).
abstract final class BrandAssets {
  static const logo = 'assets/brand/taparide_logo.png';
  static const logoWhite = 'assets/brand/taparide_logo_white.png';
  static const mark = 'assets/brand/taparide_mark.png';
  static const markWhite = 'assets/brand/taparide_mark_white.png';
  static const wordmark = 'assets/brand/taparide_wordmark.png';
  static const wordmarkWhite = 'assets/brand/taparide_wordmark_white.png';
}

/// Horizontal lockup used in headers: car-and-pin mark beside the wordmark.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.height = 30, this.onDark = false, this.showDescriptor = false});

  final double height;
  final bool onDark;
  final bool showDescriptor;

  @override
  Widget build(BuildContext context) {
    final descriptorColor = onDark ? const Color(0xFFB9D5C5) : const Color(0xFF5B6B62);
    return Semantics(
      label: 'Tap A Ride, Abuja Smart Mobility Platform',
      image: true,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(onDark ? BrandAssets.markWhite : BrandAssets.mark, height: height, filterQuality: FilterQuality.medium),
              SizedBox(width: height * 0.28),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(onDark ? BrandAssets.wordmarkWhite : BrandAssets.wordmark, height: height * 0.56, filterQuality: FilterQuality.medium),
                  if (showDescriptor) ...[
                    SizedBox(height: height * 0.12),
                    Text(
                      'Abuja Smart Mobility Platform',
                      style: TextStyle(
                          fontSize: (height * 0.34).clamp(10, 14), fontWeight: FontWeight.w600, color: descriptorColor, letterSpacing: 0.2, height: 1),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full stacked logo with tagline (Ride • Connect • Go).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 220, this.onDark = false});
  final double width;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Image.asset(
        onDark ? BrandAssets.logoWhite : BrandAssets.logo,
        width: width,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Tap A Ride. Ride, connect, go.',
      );
}
