import 'keyboard_stub.dart' if (dart.library.js_interop) 'keyboard_web.dart' as impl;

/// Phone browsers: when the on-screen keyboard is closed (Done, swipe down, back button, or the
/// password eye swapping the input), the browser drops the input but Flutter keeps the text field
/// focused, so tapping the field again does nothing until the page is reloaded. This clears that
/// stale focus as soon as the keyboard goes away, so the next tap opens the keyboard again.
/// Safe to call more than once; does nothing outside the web or on desktop browsers.
void installKeyboardFix() => impl.installKeyboardFix();
