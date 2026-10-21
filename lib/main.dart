import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
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

  // 1) ما تخلّيش أي خطأ يطيح التطبيق كامل. في release mode Flutter ما كيبينش
  //    الشاشة الحمرا، فأي exception قبل runApp = شاشة سوداء صامتة.
  FlutterError.onError = (details) {
    debugPrint('FLUTTER ERROR >>> ${details.exception}\n${details.stack}');
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('UNCAUGHT ERROR >>> $error\n$stack');
    return true;
  };

  // 2) كل خطوة ديال التهيئة عندها try/catch + timeout.
  //    إلا hung شي plugin، التطبيق ي Rao يخدم عادي بدل ما يبقى أسود.
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

  // 3) runApp ديماً — التطبيق كيبقى قابل للاستعمال حتى لو كان في مشكل.
  runApp(const MyApp());
}

/// يسمح بالسحب بالماوس على الكمبيوتر (الصفوف والشريط).
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
  @override
  void initState() {
    super.initState();
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
