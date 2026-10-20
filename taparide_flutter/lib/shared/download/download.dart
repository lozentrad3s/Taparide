import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart' as impl;

/// Saves [rows] as a CSV file (browser download on web). Returns false where unsupported.
Future<bool> downloadCsv(String fileName, List<List<Object?>> rows) => impl.saveText(fileName, toCsv(rows), 'text/csv');

String toCsv(List<List<Object?>> rows) => rows.map((r) => r.map(_cell).join(',')).join('\r\n');

String _cell(Object? v) {
  final s = v?.toString() ?? '';
  return RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}
