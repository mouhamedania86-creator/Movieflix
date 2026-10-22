/// يحول حلقات المسلسل (من get_series_info) لقائمة وحدة مرتبة: موسم ثم حلقة.
/// هكا الحلقة اللي بعد آخر حلقة في الموسم تكون أول حلقة في الموسم الجاي،
/// وما يهمش إذا episode_num جاي رقم ولا نص.
List<Map<String, dynamic>> flattenEpisodes(dynamic episodesField) {
  final seasons = <String, List<dynamic>>{};
  if (episodesField is Map) {
    episodesField.forEach((k, v) => seasons[k.toString()] = v is List ? v : <dynamic>[]);
  } else if (episodesField is List) {
    for (var i = 0; i < episodesField.length; i++) {
      final e = episodesField[i];
      seasons['${i + 1}'] = e is List ? List<dynamic>.from(e) : <dynamic>[];
    }
  }

  int num(dynamic ep) => int.tryParse('${ep['episode_num']}') ?? 0;

  final keys = seasons.keys.toList()
    ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

  final out = <Map<String, dynamic>>[];
  for (final s in keys) {
    final list = List<dynamic>.from(seasons[s]!)..sort((a, b) => num(a).compareTo(num(b)));
    for (final ep in list) {
      out.add({
        'id': ep['id'].toString(),
        'ext': (ep['container_extension'] ?? 'mp4').toString(),
        'season': int.tryParse(s) ?? 0,
        'num': num(ep),
      });
    }
  }
  return out;
}
