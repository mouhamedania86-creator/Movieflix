import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'strings.dart';

// ---------------- سجل المشاهدة ----------------
class WatchEntry {
  final String key; // vod_123 | series_456 (456 = id الحلقة)
  final String type; // vod | series
  final Map<String, dynamic> item; // الفيلم أو المسلسل
  final String mediaId; // id المستعمل في رابط التشغيل
  final String ext;
  final String title;
  final String subtitle;
  final int pos, dur, ts;
  final bool done;

  const WatchEntry({
    required this.key,
    required this.type,
    required this.item,
    required this.mediaId,
    required this.ext,
    required this.title,
    required this.subtitle,
    required this.pos,
    required this.dur,
    required this.ts,
    required this.done,
  });

  factory WatchEntry.forMovie(dynamic item) {
    final id = XtreamAPI.idOf(item, 'vod');
    return WatchEntry(
      key: 'vod_$id',
      type: 'vod',
      item: Map<String, dynamic>.from(item as Map),
      mediaId: id,
      ext: (item['container_extension'] ?? 'mp4').toString(),
      title: (item['name'] ?? '').toString(),
      subtitle: '',
      pos: 0,
      dur: 0,
      ts: 0,
      done: false,
    );
  }

  factory WatchEntry.forEpisode(dynamic seriesItem, String epId, String ext, String subtitle) {
    return WatchEntry(
      key: 'series_$epId',
      type: 'series',
      item: Map<String, dynamic>.from(seriesItem as Map),
      mediaId: epId,
      ext: ext,
      title: (seriesItem['name'] ?? '').toString(),
      subtitle: subtitle,
      pos: 0,
      dur: 0,
      ts: 0,
      done: false,
    );
  }

  String get fullTitle => subtitle.isEmpty ? title : '$title - $subtitle';
  String get itemId => XtreamAPI.idOf(item, type);
  double get fraction => dur > 0 ? (pos / dur).clamp(0.0, 1.0).toDouble() : 0.0;

  WatchEntry copyWith({int? pos, int? dur, int? ts, bool? done}) => WatchEntry(
        key: key,
        type: type,
        item: item,
        mediaId: mediaId,
        ext: ext,
        title: title,
        subtitle: subtitle,
        pos: pos ?? this.pos,
        dur: dur ?? this.dur,
        ts: ts ?? this.ts,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type,
        'item': item,
        'mediaId': mediaId,
        'ext': ext,
        'title': title,
        'subtitle': subtitle,
        'pos': pos,
        'dur': dur,
        'ts': ts,
        'done': done,
      };

  factory WatchEntry.fromJson(Map<String, dynamic> j) => WatchEntry(
        key: j['key'].toString(),
        type: j['type'].toString(),
        item: Map<String, dynamic>.from(j['item'] as Map),
        mediaId: j['mediaId'].toString(),
        ext: j['ext'].toString(),
        title: j['title'].toString(),
        subtitle: (j['subtitle'] ?? '').toString(),
        pos: (j['pos'] ?? 0) as int,
        dur: (j['dur'] ?? 0) as int,
        ts: (j['ts'] ?? 0) as int,
        done: j['done'] == true,
      );
}

// ---------------- الإشعارات الداخلية ----------------
class InboxItem {
  final int ts;
  final String title, body;
  final bool read;
  const InboxItem({required this.ts, required this.title, required this.body, required this.read});

  Map<String, dynamic> toJson() => {'ts': ts, 'title': title, 'body': body, 'read': read};
  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        ts: (j['ts'] ?? 0) as int,
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        read: j['read'] == true,
      );
}

// ---------------- التذكيرات ----------------
class Reminder {
  final int id;
  final String type; // movie | tv
  final int tmdbId;
  final String title;
  final String poster;
  final int dateMs;
  final bool fired;
  const Reminder({
    required this.id,
    required this.type,
    required this.tmdbId,
    required this.title,
    required this.poster,
    required this.dateMs,
    required this.fired,
  });

  static int idFor(String type, int tmdbId) => (type == 'tv' ? 1000000000 : 0) + tmdbId;

  Reminder copyWith({bool? fired}) => Reminder(
        id: id,
        type: type,
        tmdbId: tmdbId,
        title: title,
        poster: poster,
        dateMs: dateMs,
        fired: fired ?? this.fired,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'tmdbId': tmdbId,
        'title': title,
        'poster': poster,
        'dateMs': dateMs,
        'fired': fired,
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: (j['id'] ?? 0) as int,
        type: (j['type'] ?? 'movie').toString(),
        tmdbId: (j['tmdbId'] ?? 0) as int,
        title: (j['title'] ?? '').toString(),
        poster: (j['poster'] ?? '').toString(),
        dateMs: (j['dateMs'] ?? 0) as int,
        fired: j['fired'] == true,
      );
}

class Store {
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);
  static final ValueNotifier<int> historyVersion = ValueNotifier<int>(0);

  // 👈 ضع مفتاح TMDB الخاص بك هنا مباشرة
  // استبدل النص التالي بالمفتاح الذي حصلت عليه من themoviedb.org
  static const String _tmdbApiKey = 'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJiYjUyNWI2MDUwOGM1NWMxY2Y4ODE5Y2Y2MjcyOGIwNCIsIm5iZiI6MTc5MjU3NjM1NC45ODMsInN1YiI6IjZhZDg4YjYyMWZlYWIxYjkxMzc2NjAwZiIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.X1AdjuA9II2XNMBF92LhaCkQQfc18tA6FYyqeRdWj0g';

  static Future<void> load() async {
    unread.value = (await inbox()).where((i) => !i.read).length;
  }

  static Future<List<Map<String, dynamic>>> _readList(String key) async {
    final p = await SharedPreferences.getInstance();
    final out = <Map<String, dynamic>>[];
    for (final s in p.getStringList(key) ?? <String>[]) {
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(s) as Map));
      } catch (_) {}
    }
    return out;
  }

  static Future<void> _writeList(String key, List<Map<String, dynamic>> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(key, l.map((e) => jsonEncode(e)).toList());
  }

  // ----- سجل المشاهدة -----
  static Future<List<WatchEntry>> history() async {
    final out = <WatchEntry>[];
    for (final j in await _readList('history')) {
      try {
        out.add(WatchEntry.fromJson(j));
      } catch (_) {}
    }
    out.sort((a, b) => b.ts.compareTo(a.ts));
    return out;
  }

  static Future<WatchEntry?> entry(String key) async {
    for (final e in await history()) {
      if (e.key == key) return e;
    }
    return null;
  }

  static Future<void> saveWatch(WatchEntry e) async {
    final list = await history();
    list.removeWhere((x) => x.key == e.key);
    list.insert(0, e);
    await _writeList('history', list.take(80).map((x) => x.toJson()).toList());
    historyVersion.value++;
  }

  /// آخر مشاهدة لكل فيلم/مسلسل.
  static List<WatchEntry> _latestPerItem(List<WatchEntry> all) {
    final seen = <String>{};
    final out = <WatchEntry>[];
    for (final e in all) {
      if (seen.add('${e.type}_${e.itemId}')) out.add(e);
    }
    return out;
  }

  static List<WatchEntry> continueList(List<WatchEntry> all) =>
      _latestPerItem(all).where((e) => !e.done && e.pos >= 10).toList();

  static List<WatchEntry> watchedList(List<WatchEntry> all) =>
      _latestPerItem(all).where((e) => e.done).toList();

  // ----- الإشعارات الداخلية -----
  static Future<List<InboxItem>> inbox() async {
    final out = <InboxItem>[];
    for (final j in await _readList('inbox')) {
      try {
        out.add(InboxItem.fromJson(j));
      } catch (_) {}
    }
    return out;
  }

  static Future<void> _saveInbox(List<InboxItem> l) async {
    await _writeList('inbox', l.take(50).map((e) => e.toJson()).toList());
    unread.value = l.take(50).where((i) => !i.read).length;
  }

  static Future<void> addInbox(String title, String body) async {
    final l = await inbox();
    l.insert(0, InboxItem(ts: DateTime.now().millisecondsSinceEpoch, title: title, body: body, read: false));
    await _saveInbox(l);
  }

  static Future<void> markAllRead() async {
    final l = await inbox();
    await _saveInbox(l.map((i) => InboxItem(ts: i.ts, title: i.title, body: i.body, read: true)).toList());
  }

  static Future<void> clearInbox() async => _saveInbox([]);

  // ----- التذكيرات -----
  static Future<List<Reminder>> reminders() async {
    final out = <Reminder>[];
    for (final j in await _readList('reminders')) {
      try {
        out.add(Reminder.fromJson(j));
      } catch (_) {}
    }
    out.sort((a, b) => a.dateMs.compareTo(b.dateMs));
    return out;
  }

  static Future<bool> hasReminder(int tmdbId, String type) async {
    final id = Reminder.idFor(type, tmdbId);
    return (await reminders()).any((r) => r.id == id && !r.fired);
  }

  static Future<void> addReminder(Reminder r) async {
    final l = await reminders();
    l.removeWhere((x) => x.id == r.id);
    l.add(r);
    await _writeList('reminders', l.map((e) => e.toJson()).toList());
  }

  static Future<void> removeReminder(int id) async {
    final l = await reminders();
    l.removeWhere((x) => x.id == id);
    await _writeList('reminders', l.map((e) => e.toJson()).toList());
  }

  /// التذكيرات اللي حان وقتها تتحول لإشعار داخل التطبيق.
  static Future<void> processDue() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final l = await reminders();
    var changed = false;
    final out = <Reminder>[];
    for (final r in l) {
      if (!r.fired && r.dateMs <= now) {
        await addInbox(S.t('now_available'), r.title);
        out.add(r.copyWith(fired: true));
        changed = true;
      } else {
        out.add(r);
      }
    }
    if (changed) await _writeList('reminders', out.map((e) => e.toJson()).toList());
  }

  // ----- إعدادات -----
  static Future<String> tmdbKey() async {
    // إذا كان المستخدم قد وضع مفتاحاً في الإعدادات، نستخدمه. وإلا، نستخدم المفتاح المدمج في الكود.
    final savedKey = (await SharedPreferences.getInstance()).getString('tmdb_key') ?? '';
    return savedKey.isNotEmpty ? savedKey : _tmdbApiKey;
  }

  static Future<void> setTmdbKey(String k) async =>
      (await SharedPreferences.getInstance()).setString('tmdb_key', k.trim());

  static Future<Set<String>> seenIds() async =>
      ((await SharedPreferences.getInstance()).getStringList('seen_ids') ?? <String>[]).toSet();

  static Future<void> setSeenIds(Iterable<String> ids) async {
    final l = ids.toList();
    final capped = l.length > 300 ? l.sublist(l.length - 300) : l;
    await (await SharedPreferences.getInstance()).setStringList('seen_ids', capped);
  }

  static Future<void> clearUserData() async {
    final p = await SharedPreferences.getInstance();
    for (final k in ['favorites', 'history', 'inbox', 'reminders', 'seen_ids']) {
      await p.remove(k);
    }
    unread.value = 0;
    historyVersion.value++;
  }
}