import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'device.dart';
import 'store.dart';
import 'strings.dart';

/// مشغل بملء الشاشة:
/// - هاتف/iPhone: سحب عمودي يسار = السطوع، يمين = الصوت، أفقي = تقديم/تأخير.
/// - كمبيوتر/تلفزة: كيبورد وريموت (OK = إيقاف/تشغيل، يمين/يسار = ±10 ثواني، فوق/تحت = الصوت).
class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? fallbackUrl;
  final bool isLive;
  final WatchEntry? watch; // لحفظ التقدم و"تابع المشاهدة"
  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.fallbackUrl,
    this.isLive = false,
    this.watch,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _video;
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

    _player = Player(configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
    _video = VideoController(_player);

    _subs.add(_player.stream.position.listen((p) => _pos = p.inSeconds));
    _subs.add(_player.stream.duration.listen((d) => _dur = d.inSeconds));
    _subs.add(_player.stream.completed.listen((c) {
      if (c) _completed = true;
    }));
    _subs.add(_player.stream.error.listen(_onError));
    _saver = Timer.periodic(const Duration(seconds: 20), (_) => _save());
    _start();
  }

  Future<void> _start() async {
    Duration? start;
    final w = widget.watch;
    if (!widget.isLive && w != null) {
      final saved = await Store.entry(w.key);
      if (saved != null && !saved.done && saved.pos > 10) {
        start = Duration(seconds: saved.pos);
      }
    }
    if (!mounted) return;
    await _player.open(Media(widget.url, start: start), play: true);
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
    if (widget.isLive || w == null || _dur <= 0 || _pos < 10) return;
    final done = _completed || _pos >= _dur - 60;
    Store.saveWatch(w.copyWith(
      pos: done ? 0 : _pos,
      dur: _dur,
      ts: DateTime.now().millisecondsSinceEpoch,
      done: done,
    ));
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
    final topBar = <Widget>[
      IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 260,
        child: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
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

    return Scaffold(backgroundColor: Colors.black, body: video);
  }
}
