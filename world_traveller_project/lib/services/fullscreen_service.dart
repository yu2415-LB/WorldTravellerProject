import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class FullscreenService {
  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  static Future<void> enter() async {
    if (_isDesktop) {
      try {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
        );
        await windowManager.setFullScreen(true);
        await windowManager.focus();
        return;
      } catch (e) {
        debugPrint('windowManager error: $e');
      }
    }

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  static Future<void> exit() async {
    if (_isDesktop) {
      try {
        await windowManager.setFullScreen(false);
        await windowManager.setTitleBarStyle(
          TitleBarStyle.normal,
        );
        await windowManager.focus();
        return;
      } catch (e) {
        debugPrint('windowManager error: $e');
      }
    }

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
  }
}