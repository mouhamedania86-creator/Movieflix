import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// تخزين الردود على القرص لعرضها بدون إنترنت.
class DiskCache {
  static Directory? _dir;

  static Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  static String keyOf(String s) {
    var h = 5381;
    for (final c in s.codeUnits) {
      h = ((h << 5) + h + c) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }

  static Future<void> put(String key, String body) async {
    try {
      final d = await _directory();
      await File('${d.path}/$key.json').writeAsString(body);
    } catch (_) {}
  }

  static Future<String?> get(String key) async {
    try {
      final d = await _directory();
      final f = File('${d.path}/$key.json');
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return null;
  }

  static Future<void> clear() async {
    try {
      final d = await _directory();
      if (await d.exists()) await d.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}
