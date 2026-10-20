import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web: the three.js mascot (web/mascot/) in an iframe. Mood changes and the app's
/// pointer position are posted to it; taps come back as `tapi-tap` messages.
Widget buildMascot(String mood, double size, VoidCallback? onTap) => _WebMascot(mood: mood, onTap: onTap);

class _WebMascot extends StatefulWidget {
  const _WebMascot({required this.mood, this.onTap});
  final String mood;
  final VoidCallback? onTap;

  @override
  State<_WebMascot> createState() => _WebMascotState();
}

class _WebMascotState extends State<_WebMascot> {
  web.HTMLIFrameElement? _frame;
  late final String _initialMood = widget.mood;
  JSFunction? _onMessage;
  JSFunction? _onPointer;
  bool _pending = false;
  double _px = 0, _py = 0;

  void _post(Map<String, Object?> data) {
    try {
      _frame?.contentWindow?.postMessage(data.jsify(), web.window.location.origin.toJS);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _onMessage = ((web.MessageEvent e) {
      final frame = _frame;
      if (frame == null || e.source != frame.contentWindow) return;
      final data = e.data.dartify();
      if (data is Map && data['type'] == 'tapi-ready') _post({'type': 'tapi', 'mood': widget.mood});
    }).toJS;
    // Tapi's eyes follow the pointer anywhere in the app, not just over the mascot.
    _onPointer = ((web.PointerEvent e) {
      final frame = _frame;
      if (frame == null) return;
      final r = frame.getBoundingClientRect();
      final half = web.window.innerWidth / 2;
      _px = ((e.clientX - (r.left + r.width / 2)) / half).clamp(-1.0, 1.0);
      _py = (-(e.clientY - (r.top + r.height / 2)) / half).clamp(-1.0, 1.0);
      if (_pending) return;
      _pending = true;
      web.window.requestAnimationFrame(((num _) {
        _pending = false;
        _post({'type': 'tapi', 'pointer': [_px, _py]});
      }).toJS);
    }).toJS;
    web.window.addEventListener('message', _onMessage);
    web.window.addEventListener('pointermove', _onPointer);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _onMessage);
    web.window.removeEventListener('pointermove', _onPointer);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _WebMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _post({'type': 'tapi', 'mood': widget.mood});
  }

  /// Taps are handled by Flutter, not the iframe: the browser would otherwise send taps to the
  /// iframe even when a sheet or dialog is drawn on top of it (e.g. the assistant's close button).
  void _tap() {
    _post({'type': 'tapi', 'mood': 'celebrate'});
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) _post({'type': 'tapi', 'mood': widget.mood});
    });
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final view = HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        frame.src = 'mascot/index.html?mood=$_initialMood';
        frame.style.pointerEvents = 'none';
        frame.tabIndex = -1;
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
    // The tap target sits on top of the platform view: a detector wrapped around it would lose
    // the gesture to the platform view, which claims every pointer that reaches it.
    return Stack(fit: StackFit.expand, children: [
      view,
      MouseRegion(
        cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tap),
      ),
    ]);
  }
}
