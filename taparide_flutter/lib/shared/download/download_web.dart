import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> saveText(String fileName, String content, String mimeType) async {
  // BOM so Excel opens the naira sign and accents correctly.
  final bytes = utf8.encode('﻿$content');
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: '$mimeType;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
