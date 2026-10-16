import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web: the three.js mascot (web/mascot/) in an iframe; mood changes are posted to it.
Widget buildMascot(String mood, double size) => _WebMascot(mood: mood);

class _WebMascot extends StatefulWidget {
  const _WebMascot({required this.mood});
  final String mood;

  @override
  State<_WebMascot> createState() => _WebMascotState();
}

class _WebMascotState extends State<_WebMascot> {
  web.HTMLIFrameElement? _frame;
  late final String _initialMood = widget.mood;

  void _post(String mood) {
    try {
      _frame?.contentWindow?.postMessage({'type': 'tapi', 'mood': mood}.jsify(), '*'.toJS);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _WebMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _post(widget.mood);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        frame.src = 'mascot/index.html?mood=$_initialMood';
        frame.style.border = 'none';
        frame.style.width = '100%';
        frame.style.height = '100%';
        frame.style.background = 'transparent';
        frame.setAttribute('allowtransparency', 'true');
        frame.setAttribute('title', 'Tapi, the Tap A Ride guide');
        frame.setAttribute('loading', 'lazy');
        _frame = frame;
      },
    );
  }
}
