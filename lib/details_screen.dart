import 'package:flutter/material.dart';
import 'api.dart';
import 'episodes.dart';
import 'player_screen.dart';
import 'store.dart';
import 'strings.dart';
import 'widgets.dart';

class DetailsScreen extends StatefulWidget {
  final dynamic item;
  final String type; // vod | series | live
  const DetailsScreen({super.key, required this.item, required this.type});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final api = XtreamAPI.instance;
  late final String _id;
  Map<String, dynamic>? _info;
  List<Map<String, String>> _epg = [];
  bool _loading = true;
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _id = XtreamAPI.idOf(widget.item, widget.type);
    _load();
  }

  Future<void> _load() async {
    try {
      _isFav = await api.isFavorite(widget.type, _id);
    } catch (_) {}
    try {
      if (widget.type == 'vod') {
        _info = await api.getVodInfo(_id);
      } else if (widget.type == 'series') {
        _info = await api.getSeriesInfo(_id);
      } else {
        _epg = await api.getShortEPG(_id);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleFav() async {
    final now = await api.toggleFavorite(widget.type, widget.item);
    if (mounted) setState(() => _isFav = now);
  }

  void _play(
    String url,
    String title, {
    WatchEntry? watch,
    bool live = false,
    String? fallback,
    List<Map<String, dynamic>>? episodes,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          url: url,
          title: title,
          watch: watch,
          fallbackUrl: fallback,
          isLive: live,
          episodes: episodes,
        ),
      ),
    );
  }

  /// يرجع المواسم والحلقات بشكل موحد.
  Map<String, List<dynamic>> _episodes() {
    final e = _info?['episodes'];
    final out = <String, List<dynamic>>{};
    if (e is Map) {
      e.forEach((k, v) => out[k.toString()] = v is List ? v : <dynamic>[]);
    } else if (e is List) {
      for (var i = 0; i < e.length; i++) {
        out['${i + 1}'] = e[i] is List ? List<dynamic>.from(e[i] as List) : <dynamic>[];
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }

    final rawInfo = _info?['info'];
    final Map infoMap = rawInfo is Map ? rawInfo : {};
    final title = (infoMap['name'] ?? widget.item['name'] ?? '').toString();
    final plot = (infoMap['plot'] ?? infoMap['description'] ?? '').toString();
    final poster = posterOf(widget.item);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: const Color(0xFF0B1220),
                child: Poster(
                  url: poster,
                  fit: (widget.type == 'live' || MediaQuery.of(context).size.width >= 700)
                      ? BoxFit.contain
                      : BoxFit.cover,
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(_isFav ? Icons.favorite : Icons.favorite_border, color: Colors.red),
                onPressed: _toggleFav,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pageInset(context), vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  if (plot.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(plot, style: const TextStyle(color: Colors.grey)),
                  ],
                  const SizedBox(height: 20),
                  ..._body(title),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(String title) {
    if (widget.type == 'vod') {
      final md = _info?['movie_data'];
      final ext = (widget.item['container_extension'] ??
              (md is Map ? md['container_extension'] : null) ??
              'mp4')
          .toString();
      return [
        _playButton(S.t('watch_movie'), () {
          final w = WatchEntry.forMovie(widget.item);
          _play(api.buildMovieUrl(_id, ext), title, watch: w);
        }),
      ];
    }

    if (widget.type == 'live') {
      return [
        _playButton(
          S.t('watch_channel'),
          () => _play(api.buildLiveUrl(_id), title, live: true, fallback: api.buildLiveUrlTs(_id)),
        ),
        const SizedBox(height: 20),
        if (_epg.isNotEmpty) ...[
          Text(S.t('epg'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._epg.map((e) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e['title'] ?? ''),
                subtitle: Text(e['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text(e['start'] ?? '', style: const TextStyle(fontSize: 11)),
              )),
        ],
      ];
    }

    // مسلسل
    final eps = _episodes();
    if (eps.isEmpty) return [Text(S.t('no_episodes'))];
    final seasons = eps.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return [
      Text(S.t('seasons'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      for (final s in seasons)
        ExpansionTile(
          title: Text('${S.t('season')} $s'),
          children: [
            for (final ep in eps[s]!)
              ListTile(
                leading: const Icon(Icons.play_circle, color: Color(0xFF14B8A6)),
                title: Text('${S.t('episode')} ${ep['episode_num'] ?? ''}'),
                subtitle: (ep['title'] ?? '').toString().isEmpty ? null : Text(ep['title'].toString()),
                onTap: () {
                  final epId = ep['id'].toString();
                  final ext = (ep['container_extension'] ?? 'mp4').toString();
                  final sub = 'S$s E${ep['episode_num'] ?? ''}';
                  final w = WatchEntry.forEpisode(widget.item, epId, ext, sub);
                  _play(
                    api.buildSeriesUrl(epId, ext),
                    w.fullTitle,
                    watch: w,
                    episodes: flattenEpisodes(_info?['episodes']),
                  );
                },
              ),
          ],
        ),
    ];
  }

  Widget _playButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF14B8A6), foregroundColor: Colors.white),
        onPressed: onPressed,
        icon: const Icon(Icons.play_arrow),
        label: Text(label),
      ),
    );
  }
}
