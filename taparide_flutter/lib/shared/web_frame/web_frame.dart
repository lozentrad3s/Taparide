import 'package:flutter/widgets.dart';

import 'web_frame_stub.dart' if (dart.library.js_interop) 'web_frame_web.dart' as impl;

/// Embeds another web app (web only). [fallback] shows on platforms without an HTML view.
class WebFrame extends StatelessWidget {
  const WebFrame({super.key, required this.url, required this.title, required this.fallback, this.allow = 'geolocation; microphone'});
  final String url;
  final String title;
  final String allow;
  final Widget fallback;

  static bool get supported => impl.supported;

  @override
  Widget build(BuildContext context) => impl.supported ? impl.buildFrame(url, title, allow) : fallback;
}
