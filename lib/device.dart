import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

/// معرفة نوع الجهاز: هاتف، تلفزة Android TV، كمبيوتر، أو iPhone.
class Device {
  static bool isTv = false;

  static bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  static bool get isIOS => Platform.isIOS;

  /// هاتف أو تابلت بلمس (Android أو iPhone).
  static bool get isTouchMobile => (Platform.isAndroid && !isTv) || Platform.isIOS;

  /// تلفزة أو كمبيوتر: تحكم بالكيبورد/الريموت بدل اللمس.
  static bool get useDesktopControls => isDesktop || isTv;

  static Future<void> init() async {
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        isTv = info.systemFeatures.contains('android.software.leanback');
      } catch (_) {}
    }
  }
}
