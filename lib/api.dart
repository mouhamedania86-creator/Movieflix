import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'disk_cache.dart';

class XtreamAPI {
  XtreamAPI._();
  static final XtreamAPI instance = XtreamAPI._();

  String server = '';
  String username = '';
  String password = '';
  final Map<String, List<dynamic>> _cache = {};
  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  bool get isLoggedIn => server.isNotEmpty && username.isNotEmpty;

  void clearMemory() => _cache.clear();

  // ---------------- الجلسة ----------------
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    server = p.getString('server') ?? '';
    username = p.getString('username') ?? '';
    password = p.getString('password') ?? '';

    // 👈 رابط ملف الإعدادات على GitHub
    const String configUrl = 'https://raw.githubusercontent.com/mouhamedania86-creator/Update/main/server.json';

    try {
      final res = await http.get(Uri.parse(configUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        server = data['server'] ?? server;
        username = data['username'] ?? username;
        password = data['password'] ?? password;
        
        await p.setString('server', server);
        await p.setString('username', username);
        await p.setString('password', password);
        return; 
      }
    } catch (_) {
      // إذا فشل الاتصال، نستخدم المحفوظ
    }

    // إذا كانت الذاكرة فارغة، نضع Ultra4K كافتراضي
    if (server.isEmpty) {
      server = 'http://ultra4k.gamerdz1517.com:80';
      username = 'ultra4k';
      password = 'gamerdz1517';
      await p.setString('server', server);
      await p.setString('username', username);
      await p.setString('password', password);
    }
  }

  static String _normalize(String s) {
    var v = s.trim();
    if (v.isEmpty) return v;
    if (v.startsWith('https://')) {
      v = v.replaceFirst('https://', 'http://');
    } else if (!v.startsWith('http://')) {
      v = 'http://$v';
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  Future<String?> login(String s, String u, String p) async {
    final old = [server, username, password];
    void restore() {
      server = old[0];
      username = old[1];
      password = old[2];
    }

    server = _normalize(s);
    username = u.trim();
    password = p.trim();
    _cache.clear();
    try {
      final data = await _fetch('', cache: false);
      final info = data is Map ? data['user_info'] : null;
      if (info is Map && '${info['auth']}' == '1') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('server', server);
        await prefs.setString('username', username);
        await prefs.setString('password', password);
        return null;
      }
      restore();
      return 'bad_creds';
    } catch (_) {
      restore();
      return 'conn_fail';
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server');
    await prefs.remove('username');
    await prefs.remove('password');
    server = '';
    username = '';
    password = '';
    _cache.clear();
    await DiskCache.clear();
  }

  Uri _uri(Map<String, String> q) {
    final base = Uri.parse('$server/player_api.php');
    return base.replace(queryParameters: {
      'username': username,
      'password': password,
      ...q,
    });
  }

  Future<dynamic> _fetch(String action,
      {Map<String, String> extra = const {}, bool cache = true}) async {
    final q = <String, String>{if (action.isNotEmpty) 'action': action, ...extra};
    final ck = DiskCache.keyOf('$server|$username|$q');
    
    final httpClient = HttpClient()
      ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);
    final client = IOClient(httpClient);

    try {
      final res = await client.get(
        _uri(q),
        headers: {
          'User-Agent': 'okhttp/3.12.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 60));
      
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      
      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      final data = json.decode(body);
      
      if (cache && action.isNotEmpty && ((data is List && data.isNotEmpty) || (data is Map && data.isNotEmpty))) {
        DiskCache.put(ck, body);
      }
      offline.value = false;
      return data;
    } catch (e) {
      if (cache && action.isNotEmpty) {
        final body = await DiskCache.get(ck);
        if (body != null) {
          offline.value = true;
          return json.decode(body);
        }
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<List<dynamic>> getCategories(String type) async {
    try {
      final data = await _fetch('get_${type}_categories');
      return data is List ? data : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<dynamic>> getStreams(String type, {String? categoryId}) async {
    final key = '$type:${categoryId ?? 'all'}';
    if (_cache.containsKey(key)) return _cache[key]!;
    final action = type == 'vod'
        ? 'get_vod_streams'
        : type == 'series'
            ? 'get_series'
            : 'get_live_streams';
    final data = await _fetch(action, extra: {if (categoryId != null) 'category_id': categoryId});
    final list = data is List ? List<dynamic>.from(data) : <dynamic>[];
    if (list.isNotEmpty) _cache[key] = list;
    return list;
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return [];
    final out = <Map<String, dynamic>>[];
    for (final type in ['vod', 'series', 'live']) {
      List<dynamic> list = [];
      try {
        list = await getStreams(type);
      } catch (_) {}
      for (final item in list) {
        if ((item['name'] ?? '').toString().toLowerCase().contains(q)) {
          out.add({...Map<String, dynamic>.from(item as Map), '_type': type});
        }
      }
      if (out.length >= 200) break;
    }
    return out.take(200).toList();
  }

  Future<Map<String, dynamic>?> getVodInfo(String id) async {
    final data = await _fetch('get_vod_info', extra: {'vod_id': id});
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<Map<String, dynamic>?> getSeriesInfo(String id) async {
    final data = await _fetch('get_series_info', extra: {'series_id': id});
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static String _b64(dynamic v) {
    final s = (v ?? '').toString();
    try {
      return utf8.decode(base64.decode(s));
    } catch (_) {
      return s;
    }
  }

  Future<List<Map<String, String>>> getShortEPG(String id) async {
    final data = await _fetch('get_short_epg', extra: {'stream_id': id, 'limit': '10'}, cache: false);
    if (data is! Map || data['epg_listings'] is! List) return [];
    return (data['epg_listings'] as List)
        .map<Map<String, String>>((e) => {
              'title': _b64(e['title']),
              'description': _b64(e['description']),
              'start': (e['start'] ?? '').toString(),
            })
        .toList();
  }

  String get _cred => '${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}';
  String buildMovieUrl(String id, String ext) => '$server/movie/$_cred/$id.$ext';
  String buildSeriesUrl(String id, String ext) => '$server/series/$_cred/$id.$ext';
  String buildLiveUrl(String id) => '$server/live/$_cred/$id.m3u8';
  String buildLiveUrlTs(String id) => '$server/live/$_cred/$id.ts';

  static String idOf(dynamic item, String type) =>
      (type == 'series' ? item['series_id'] : item['stream_id']).toString();

  Future<List<Map<String, dynamic>>> getFavorites() async {
    final p = await SharedPreferences.getInstance();
    final out = <Map<String, dynamic>>[];
    for (final s in p.getStringList('favorites') ?? <String>[]) {
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(s) as Map));
      } catch (_) {}
    }
    return out;
  }

  Future<bool> isFavorite(String type, String id) async {
    final favs = await getFavorites();
    return favs.any((f) => f['_type'] == type && idOf(f, type) == id);
  }

  Future<bool> toggleFavorite(String type, dynamic item) async {
    final p = await SharedPreferences.getInstance();
    final favs = await getFavorites();
    final id = idOf(item, type);
    final idx = favs.indexWhere((f) => f['_type'] == type && idOf(f, type) == id);
    if (idx >= 0) {
      favs.removeAt(idx);
    } else {
      favs.add({...Map<String, dynamic>.from(item as Map), '_type': type});
    }
    await p.setStringList('favorites', favs.map((f) => jsonEncode(f)).toList());
    return idx < 0;
  }
}
