import 'dart:convert';
import 'package:http/http.dart' as http;
import 'disk_cache.dart';

class Upcoming {
  final int id;
  final String type; // movie | tv
  final String title, overview, poster, backdrop;
  final DateTime? date;
  const Upcoming({
    required this.id,
    required this.type,
    required this.title,
    required this.overview,
    required this.poster,
    required this.backdrop,
    required this.date,
  });

  String get posterUrl => poster.isEmpty ? '' : 'https://image.tmdb.org/t/p/w342$poster';
  String get backdropUrl => backdrop.isEmpty ? '' : 'https://image.tmdb.org/t/p/w780$backdrop';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'overview': overview,
        'poster': poster,
        'backdrop': backdrop,
        'date': date?.toIso8601String(),
      };

  factory Upcoming.fromJson(Map<String, dynamic> j) => Upcoming(
        id: (j['id'] ?? 0) as int,
        type: (j['type'] ?? 'movie').toString(),
        title: (j['title'] ?? '').toString(),
        overview: (j['overview'] ?? '').toString(),
        poster: (j['poster'] ?? '').toString(),
        backdrop: (j['backdrop'] ?? '').toString(),
        date: DateTime.tryParse((j['date'] ?? '').toString()),
      );
}

/// الأفلام والمسلسلات القادمة من TMDB (يحتاج مفتاح API مجاني من المستخدم).
class Tmdb {
  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<List<dynamic>> _get(String key, String path, Map<String, String> q) async {
    final bearer = key.startsWith('eyJ'); // مفتاح v4
    final uri = Uri.https('api.themoviedb.org', '/3/$path', {
      if (!bearer) 'api_key': key,
      ...q,
    });
    final res = await http
        .get(uri, headers: bearer ? {'Authorization': 'Bearer $key'} : null)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('TMDB ${res.statusCode}');
    final data = json.decode(utf8.decode(res.bodyBytes));
    return data is Map && data['results'] is List ? data['results'] as List : <dynamic>[];
  }

  static Upcoming? _parse(dynamic j, String type) {
    final poster = (j['poster_path'] ?? '').toString();
    final date = DateTime.tryParse((j['release_date'] ?? j['first_air_date'] ?? '').toString());
    if (poster.isEmpty || date == null) return null;
    return Upcoming(
      id: (j['id'] ?? 0) as int,
      type: type,
      title: (j['title'] ?? j['name'] ?? '').toString(),
      overview: (j['overview'] ?? '').toString(),
      poster: poster,
      backdrop: (j['backdrop_path'] ?? '').toString(),
      date: date,
    );
  }

  static Future<List<Upcoming>> upcoming(String key, String lang) async {
    final now = DateTime.now();
    final from = _d(now.add(const Duration(days: 1)));
    final to = _d(now.add(const Duration(days: 180)));
    final ck = DiskCache.keyOf('tmdb|$lang');
    try {
      final base = {'language': lang, 'sort_by': 'popularity.desc', 'include_adult': 'false'};
      final results = await Future.wait([
        _get(key, 'discover/movie',
            {...base, 'primary_release_date.gte': from, 'primary_release_date.lte': to}),
        _get(key, 'discover/tv', {...base, 'first_air_date.gte': from, 'first_air_date.lte': to}),
      ]);
      final list = <Upcoming>[];
      for (final j in results[0]) {
        final u = _parse(j, 'movie');
        if (u != null) list.add(u);
      }
      for (final j in results[1]) {
        final u = _parse(j, 'tv');
        if (u != null) list.add(u);
      }
      list.sort((a, b) => a.date!.compareTo(b.date!));
      final out = list.take(24).toList();
      DiskCache.put(ck, jsonEncode(out.map((e) => e.toJson()).toList()));
      return out;
    } catch (_) {
      final cached = await DiskCache.get(ck);
      if (cached != null) {
        return (jsonDecode(cached) as List)
            .map((e) => Upcoming.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      rethrow;
    }
  }
}
