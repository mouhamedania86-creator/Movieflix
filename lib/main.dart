import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'device.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'notifier.dart';
import 'store.dart';
import 'strings.dart';

/// الأخطاء اللي وقعوا أثناء التهيئة (باش تبان للمستخدم بدل شاشة سوداء).
final List<String> initErrors = <String>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    debugPrint('FLUTTER ERROR >>> ${details.exception}\n${details.stack}');
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('UNCAUGHT ERROR >>> $error\n$stack');
    return true;
  };

  Future<void> step(String name, Future<void> Function() fn) async {
    try {
      await fn().timeout(const Duration(seconds: 15));
    } catch (e) {
      initErrors.add('$name → $e');
      debugPrint('INIT STEP "$name" FAILED >>> $e');
    }
  }

  await step('MediaKit', () async => MediaKit.ensureInitialized());
  await step('Device', Device.init);
  await step('XtreamAPI', () => XtreamAPI.instance.load());
  await step('Strings', S.load);
  await step('Store', Store.load);
  await step('Notifier', Notifier.init);

  runApp(const MyApp());
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: S.lang,
      builder: (context, lang, _) => MaterialApp(
        title: 'MovieFlix',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const AppScrollBehavior(),
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF14B8A6),
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0F172A)),
        ),
        builder: (context, child) => Directionality(
          textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showUpdate = false;
  String _updateUrl = '';

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    try {
      // 👈 ضع رابط ملف server.json هنا
      const String configUrl = 'https://raw.githubusercontent.com/mouhamedania86-creator/Update/main/server.json';
      final res = await http.get(Uri.parse(configUrl)).timeout(const Duration(seconds: 5));
      
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final bool forceUpdate = data['force_update'] ?? false;
        final String latestVersion = data['latest_version'] ?? '1.0.0';
        final String updateUrl = data['update_url'] ?? '';

        // إصدار التطبيق الحالي (يجب أن يطابق pubspec.yaml)
        const String currentVersion = '1.0.1';

        // 👈 إذا كان التحديث إجبارياً، والإصدار الحالي أقل من المطلوب
        if (forceUpdate && currentVersion != latestVersion) {
          setState(() {
            _showUpdate = true;
            _updateUrl = updateUrl;
          });
          return;
        }
      }
    } catch (_) {}

    // إذا لم يوجد تحديث، ننتقل للشاشة الرئيسية
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => XtreamAPI.instance.isLoggedIn ? const HomeScreen() : const LoginScreen(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showUpdate) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update, size: 80, color: Colors.orange),
                const SizedBox(height: 20),
                const Text('تحديث إجباري', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text('يجب عليك تحديث التطبيق إلى الإصدار الجديد للاستمرار.', textAlign: TextAlign.center),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF14B8A6)),
                    onPressed: () {
                      launchUrl(Uri.parse(_updateUrl), mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('تحميل التحديث الآن'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_fill, size: 90, color: Color(0xFF14B8A6)),
              const SizedBox(height: 16),
              const Text('MovieFlix', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              if (initErrors.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x1AFF5252),
                    border: Border.all(color: Colors.redAccent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      const Text('أخطاء التهيئة:',
                          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      for (final e in initErrors)
                        Text(e,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
