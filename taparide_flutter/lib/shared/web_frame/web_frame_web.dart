import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const supported = true;

Widget buildFrame(String url, String title, String allow) => HtmlElementView.fromTagName(
      key: ValueKey(url),
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        frame.src = url;
        frame.style.border = 'none';
        frame.style.width = '100%';
        frame.style.height = '100%';
        frame.setAttribute('title', title);
        frame.setAttribute('allow', allow);
        frame.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
      },
    );
