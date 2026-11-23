import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

bool _installed = false;

void installKeyboardFix() {
  if (_installed) return;
  _installed = true;
  // Only touch devices have an on-screen keyboard.
  if (web.window.navigator.maxTouchPoints <= 0) return;
  final viewport = web.window.visualViewport;
  if (viewport == null) return;

  var width = viewport.width;
  var fullHeight = viewport.height;
  var keyboardOpen = false;

  void onResize(web.Event _) {
    final h = viewport.height;
    // Turning the phone resets what "full height" means.
    if ((viewport.width - width).abs() > 1) {
      width = viewport.width;
      fullHeight = h;
      keyboardOpen = false;
      return;
    }
    if (h > fullHeight) fullHeight = h;
    // The keyboard takes at least ~120px; a smaller change is the browser bar moving.
    if (h < fullHeight - 120) {
      keyboardOpen = true;
      return;
    }
    if (keyboardOpen && h >= fullHeight - 60) {
      keyboardOpen = false;
      _dropStaleTextFocus();
    }
  }

  viewport.addEventListener('resize', onResize.toJS);
  // The browser can also drop the input without resizing (e.g. the password field switching
  // between hidden and visible text). Check when focus leaves an input.
  web.document.addEventListener(
    'focusout',
    ((web.Event e) {
      final target = e.target;
      if (target is! web.HTMLInputElement && target is! web.HTMLTextAreaElement) return;
      // Give the engine a moment: when it swaps inputs it focuses the new one straight away.
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        final active = web.document.activeElement;
        final stillTyping = active != null && (active.tagName == 'INPUT' || active.tagName == 'TEXTAREA');
        if (!stillTyping) _dropStaleTextFocus();
      });
    }).toJS,
  );
}

/// Unfocuses the focused text field, if any, so the next tap focuses it afresh.
void _dropStaleTextFocus() {
  final focus = FocusManager.instance.primaryFocus;
  final context = focus?.context;
  if (focus == null || context == null || !context.mounted) return;
  final isTextField = context.widget is EditableText || context.findAncestorWidgetOfExactType<EditableText>() != null;
  if (isTextField) focus.unfocus();
}
