import 'package:flutter/material.dart';

import 'mascot_stub.dart' if (dart.library.js_interop) 'mascot_web.dart' as impl;

/// Tapi's moods (see web/mascot/mascot.js).
enum MascotMood { idle, wave, think, celebrate, sleep }

/// Tapi, the Tap A Ride mascot: a 3D three.js character on the web, the logo pin elsewhere.
/// [onTap] fires when the rider taps Tapi (used to open the assistant).
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.mood = MascotMood.idle, this.size = 120, this.semanticLabel = 'Tapi, the Tap A Ride guide', this.onTap});
  final MascotMood mood;
  final double size;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        image: onTap == null,
        button: onTap != null,
        onTap: onTap,
        child: ExcludeSemantics(child: SizedBox(width: size, height: size, child: impl.buildMascot(mood.name, size, onTap))),
      );
}
