import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'device.dart';
import 'store.dart';
import 'strings.dart';
import 'api.dart';

class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? fallbackUrl;
  final bool isLive;
  final WatchEntry? watch;
  
  // 👈 خصائص التنقل بين الحلقات
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  final List<dynamic>? allEpisodes;

  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.fallbackUrl,
    this.isLive = false,
    this.watch,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.allEpisodes,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late Player _player;
  late VideoController _video;
  final List<StreamSubscription> _subs = [];
  Timer? _saver;
  bool _triedFallback = false;
  bool _completed = false;
  int _pos = 0;
  int _dur = 0;

  @override
  void initState() {
    super.initState();
    if (Device.isTouchMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    _initPlayer(widget.url);
    _saver = Timer.periodic(const Duration(seconds: 20), (_) => _save());
  }

  void _initPlayer(String url) {
    _player = Player(configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
    _video = VideoController(_player);

    _subs.add(_player.stream.position.listen((p) => _pos = p.inSeconds));
    _subs.add(_player.stream.duration.listen((d) => _dur = d.inSeconds));
    _subs.add(_player.stream.completed.listen((c) {
      if (c) _completed = true;
    }));
    _subs.add(_player.stream.error.listen(_onError));
    
    _start(url);
  }

  Future<void> _start(String url) async {
    Duration? start;
    final w = widget.watch;
    if (!widget.isLive && w != null) {
      final saved = await Store.entry(w.key);
      if (saved != null && !saved.done && saved.pos > 10) {
        start = Duration(seconds: saved.pos);
      }
    }
    if (!mounted) return;
    await _player.open(Media(url, start: start), play: true);
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
    final w = widget.watch;
    if (widget.isLive || w == null || _dur <= 0) return;
    
    final done = _completed || _pos >= _dur - 60;
    Store.saveWatch(w.copyWith(
      pos: done ? 0 : _pos,
      dur: _dur,
      ts: DateTime.now().millisecondsSinceEpoch,
      done: done,
    ));
  }

  void _switchEpisode(dynamic ep) {
    _save(); // حفظ الحلقة الحالية
    _saver?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();

    final epId = ep['id'].toString();
    final ext = (ep['container_extension'] ?? 'mp4').toString();
    final url = XtreamAPI.instance.buildSeriesUrl(epId, ext);

    setState(() {
      widget = PlayerScreen(
        url: url,
        title: '${widget.title.split(' - ')[0]} - S${widget.seasonNumber} E${ep['episode_num']}',
        watch: WatchEntry.forEpisode(
          widget.watch!.item, 
          epId, 
          ext, 
          'S${widget.seasonNumber} E${ep['episode_num']}'
        ),
        isLive: false,
        seriesId: widget.seriesId,
        seasonNumber: widget.seasonNumber,
        episodeNumber: ep['episode_num'],
        allEpisodes: widget.allEpisodes,
      );
    });

    _pos = 0;
    _dur = 0;
    _completed = false;
    _initPlayer(url);
    _saver = Timer.periodic(const Duration(seconds: 20), (_) => _save());
  }

  @override
  void dispose() {
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
    // البحث عن الحلقة السابقة والتالية
    dynamic prevEp, nextEp;
    if (widget.allEpisodes != null && widget.episodeNumber != null) {
      for (var e in widget.allEpisodes!) {
        if (e['episode_num'] == widget.episodeNumber! - 1) prevEp = e;
        if (e['episode_num'] == widget.episodeNumber! + 1) nextEp = e;
      }
    }

    final topBar = <Widget>[
      IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 200,
        child: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      const Spacer(),
      // 👈 زر الحلقة السابقة
      if (prevEp != null)
        IconButton(
          icon: const Icon(Icons.skip_previous, color: Colors.white),
          onPressed: () => _switchEpisode(prevEp),
        ),
      // 👈 زر الحلقة التالية
      if (nextEp != null)
        IconButton(
          icon: const Icon(Icons.skip_next, color: Colors.white),
          onPressed: () => _switchEpisode(nextEp),
        ),
      // 👈 زر سرعة التشغيل
      PopupMenuButton<double>(
        icon: const Icon(Icons.speed, color: Colors.white),
        initialValue: _player.state.rate,
        onSelected: (value) {
          _player.setRate(value);
          setState(() {});
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 0.5, child: Text('0.5x')),
          const PopupMenuItem(value: 0.75, child: Text('0.75x')),
          const PopupMenuItem(value: 1.0, child: Text('عادي (1x)')),
          const PopupMenuItem(value: 1.25, child: Text('1.25x')),
          const PopupMenuItem(value: 1.5, child: Text('1.5x')),
          const PopupMenuItem(value: 2.0, child: Text('2.0x')),
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

    // 👈 مستشعر النقر المزدوج
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onDoubleTapDown: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          final tapPosition = details.globalPosition.dx;

          if (tapPosition > screenWidth / 2) {
            final newPos = _player.state.position + const Duration(seconds: 10);
            _player.seek(newPos);
          } else {
            var newPos = _player.state.position - const Duration(seconds: 10);
            if (newPos < Duration.zero) newPos = Duration.zero;
            _player.seek(newPos);
          }
        },
        child: video,
      ),
    );
  }
}
