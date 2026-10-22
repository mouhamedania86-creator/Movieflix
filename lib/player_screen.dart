import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'api.dart';
import 'device.dart';
import 'episodes.dart';
import 'store.dart';
import 'strings.dart';

class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? fallbackUrl;
  final bool isLive;
  final WatchEntry? watch;

  /// كل حلقات المسلسل مرتبة (من flattenEpisodes). إذا ما تعطاتش،
  /// المشغل يجيبها وحدو للمسلسلات.
  final List<Map<String, dynamic>>? episodes;

  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.fallbackUrl,
    this.isLive = false,
    this.watch,
    this.episodes,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // مشغل واحد طول الوقت: نبدلو الحلقة بـ open() بلا ما نعاودو نصنعو Player جديد
  late final Player _player;
  late final VideoController _video;
  final List<StreamSubscription> _subs = [];
  Timer? _saver;

  bool _triedFallback = false;
  bool _completed = false;
  bool _resumePending = false; // ما نحفظوش التقدم وقت استرجاع آخر نقطة
  bool _advancing = false;
  int _pos = 0;
  int _dur = 0;
  int _gen = 0; // يلغي العمليات القديمة كي تتبدل الحلقة بسرعة

  late String _title;
  WatchEntry? _watch;
  List<Map<String, dynamic>>? _episodes;
  int _index = -1;

  bool get _hasPrev => _episodes != null && _index > 0;
  bool get _hasNext => _episodes != null && _index >= 0 && _index < _episodes!.length - 1;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _watch = widget.watch;
    _episodes = widget.episodes;
    _index = _indexOfCurrent();

    if (Device.isTouchMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    _player = Player(configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
    _video = VideoController(_player);

    _subs.add(_player.stream.position.listen((p) => _pos = p.inSeconds));
    _subs.add(_player.stream.duration.listen((d) => _dur = d.inSeconds));
    _subs.add(_player.stream.completed.listen(_onCompleted));
    _subs.add(_player.stream.error.listen(_onError));
    _saver = Timer.periodic(const Duration(seconds: 20), (_) => _save());

    _open(widget.url);
    _ensureEpisodes();
  }

  int _indexOfCurrent() {
    final w = _watch;
    final eps = _episodes;
    if (w == null || eps == null) return -1;
    return eps.indexWhere((e) => e['id'] == w.mediaId);
  }

  /// كي نكملو من "تابع المشاهدة" ما عندناش قائمة الحلقات، نجيبوها.
  Future<void> _ensureEpisodes() async {
    final w = _watch;
    if (_episodes != null || w == null || w.type != 'series') return;
    try {
      final info = await XtreamAPI.instance.getSeriesInfo(w.itemId);
      final flat = flattenEpisodes(info?['episodes']);
      final idx = flat.indexWhere((e) => e['id'] == w.mediaId);
      if (!mounted || idx < 0) return;
      setState(() {
        _episodes = flat;
        _index = idx;
      });
    } catch (_) {}
  }

  /// يفتح الرابط ويكمل من آخر نقطة محفوظة.
  Future<void> _open(String url) async {
    final gen = ++_gen;
    Duration? start;
    final w = _watch;
    if (!widget.isLive && w != null) {
      final saved = await Store.entry(w.key);
      if (saved != null && !saved.done && saved.pos > 10) {
        start = Duration(seconds: saved.pos);
      }
    }
    if (!mounted || gen != _gen) return;

    _resumePending = start != null;
    try {
      await _player.open(Media(url, start: start), play: true);
      if (start != null) await _seekWhenReady(start, gen);
    } finally {
      if (gen == _gen) _resumePending = false;
    }
  }

  /// بعض السيرفرات تتجاهل start، فنعملو seek صريح بعد ما المدة تتعرف.
  Future<void> _seekWhenReady(Duration target, int gen) async {
    try {
      if (_player.state.duration <= Duration.zero) {
        await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 25));
      }
      for (var i = 0; i < 3; i++) {
        if (!mounted || gen != _gen) return;
        final cur = _player.state.position;
        if ((target - cur).inSeconds.abs() <= 5) return;
        await _player.seek(target);
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } catch (_) {}
  }

  Future<void> _goTo(int i) async {
    final eps = _episodes;
    final w = _watch;
    if (eps == null || w == null || i < 0 || i >= eps.length) return;

    _save(); // نحفظو الحلقة الحالية قبل ما نبدلو
    final ep = eps[i];
    final sub = 'S${ep['season']} E${ep['num']}';
    final nw = WatchEntry.forEpisode(w.item, ep['id'] as String, ep['ext'] as String, sub);

    setState(() {
      _index = i;
      _watch = nw;
      _title = nw.fullTitle;
      _completed = false;
      _pos = 0;
      _dur = 0;
    });
    await _open(XtreamAPI.instance.buildSeriesUrl(nw.mediaId, nw.ext));
  }

  void _onCompleted(bool c) {
    if (!c || widget.isLive) return;
    // إذا انقطع البث قبل النهاية ما نعتبروهاش خلصت
    if (_dur > 0 && _pos < _dur - 90) return;
    _completed = true;
    if (_hasNext && !_advancing) {
      _advancing = true;
      _goTo(_index + 1).whenComplete(() => _advancing = false);
    }
  }

  void _onError(String error) {
    if (!mounted) return;
    if (widget.isLive && widget.fallbackUrl != null && !_triedFallback) {
      _triedFallback = true;
      _player.open(Media(widget.fallbackUrl!), play: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('player_fail'))));
    }
  }

  void _save() {
    final w = _watch;
    if (widget.isLive || w == null || _resumePending) return;
    final dur = _dur > 0 ? _dur : _player.state.duration.inSeconds;
    if (dur <= 0) return;
    final done = _completed || (dur > 120 && _pos >= dur - 60);
    if (!done && _pos < 10) return; // ما نمسحوش تقدم قديم بوقت قصير
    Store.saveWatch(w.copyWith(
      pos: done ? 0 : _pos,
      dur: dur,
      ts: DateTime.now().millisecondsSinceEpoch,
      done: done,
    ));
  }

  @override
  void dispose() {
    _gen++;
    _saver?.cancel();
    _save();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    if (Device.isTouchMobile) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    void seekBy(int seconds) {
      var p = _player.state.position + Duration(seconds: seconds);
      if (p < Duration.zero) p = Duration.zero;
      _player.seek(p);
    }

    void volumeBy(double d) {
      _player.setVolume((_player.state.volume + d).clamp(0.0, 100.0).toDouble());
    }

    return {
      const SingleActivator(LogicalKeyboardKey.mediaPlay): () => _player.play(),
      const SingleActivator(LogicalKeyboardKey.mediaPause): () => _player.pause(),
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () => _player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () {
        if (_hasNext) _goTo(_index + 1);
      },
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () {
        if (_hasPrev) _goTo(_index - 1);
      },
      const SingleActivator(LogicalKeyboardKey.space): () => _player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.select): () => _player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.enter): () => _player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seekBy(-10),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => seekBy(10),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => volumeBy(5),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => volumeBy(-5),
    };
  }

  @override
  Widget build(BuildContext context) {
    final topBar = <Widget>[
      IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 200,
        child: Text(
          _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      const Spacer(),
      if (_hasPrev)
        IconButton(
          icon: const Icon(Icons.skip_previous, color: Colors.white),
          onPressed: () => _goTo(_index - 1),
        ),
      if (_hasNext)
        IconButton(
          icon: const Icon(Icons.skip_next, color: Colors.white),
          onPressed: () => _goTo(_index + 1),
        ),
      PopupMenuButton<double>(
        icon: const Icon(Icons.speed, color: Colors.white),
        initialValue: _player.state.rate,
        onSelected: (value) {
          _player.setRate(value);
          setState(() {});
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 0.5, child: Text('0.5x')),
          PopupMenuItem(value: 0.75, child: Text('0.75x')),
          PopupMenuItem(value: 1.0, child: Text('1x')),
          PopupMenuItem(value: 1.25, child: Text('1.25x')),
          PopupMenuItem(value: 1.5, child: Text('1.5x')),
          PopupMenuItem(value: 2.0, child: Text('2x')),
        ],
      ),
    ];

    final Widget video;
    if (Device.useDesktopControls) {
      final t = MaterialDesktopVideoControlsThemeData(
        topButtonBar: topBar,
        seekBarPositionColor: Colors.red,
        seekBarThumbColor: Colors.red,
        keyboardShortcuts: _shortcuts(),
      );
      video = MaterialDesktopVideoControlsTheme(
        normal: t,
        fullscreen: t,
        child: Video(controller: _video, controls: MaterialDesktopVideoControls),
      );
    } else {
      final t = MaterialVideoControlsThemeData(
        volumeGesture: true,
        brightnessGesture: true,
        seekGesture: true,
        seekBarPositionColor: Colors.red,
        seekBarThumbColor: Colors.red,
        topButtonBar: topBar,
      );
      video = MaterialVideoControlsTheme(
        normal: t,
        fullscreen: t,
        child: Video(controller: _video, controls: MaterialVideoControls),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Device.isTouchMobile
          ? GestureDetector(
              onDoubleTapDown: (details) {
                final w = MediaQuery.of(context).size.width;
                final cur = _player.state.position;
                if (details.globalPosition.dx > w / 2) {
                  _player.seek(cur + const Duration(seconds: 10));
                } else {
                  final p = cur - const Duration(seconds: 10);
                  _player.seek(p < Duration.zero ? Duration.zero : p);
                }
              },
              child: video,
            )
          : video,
    );
  }
}
