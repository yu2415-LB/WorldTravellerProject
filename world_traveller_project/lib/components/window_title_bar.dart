import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// True when the app runs on a desktop platform where drawing the window
/// controls (minimise / maximise / close) makes sense.
bool get isDesktopWindowPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Custom desktop title bar.
class WindowTitleBar extends StatefulWidget {
  final Widget child;

  const WindowTitleBar({super.key, required this.child});

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (isDesktopWindowPlatform) {
      windowManager.addListener(this);
      _syncMaximizedState();
    }
  }

  @override
  void dispose() {
    if (isDesktopWindowPlatform) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncMaximizedState() async {
    final maximized = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() => _isMaximized = maximized);
  }

  @override
  void onWindowMaximize() => _syncMaximizedState();

  @override
  void onWindowUnmaximize() => _syncMaximizedState();

  @override
  Widget build(BuildContext context) {
    if (!isDesktopWindowPlatform) {
      return widget.child;
    }

    return Column(
      children: [
        _buildTitleBar(context),
        Expanded(child: widget.child),
      ],
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () async {
                    if (await windowManager.isMaximized()) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                    _syncMaximizedState();
                  },
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(
                        Icons.travel_explore,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'World Traveller',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _WindowButton(
              icon: Icons.remove,
              tooltip: 'Riduci a icona',
              onPressed: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
              tooltip: _isMaximized ? 'Ripristina' : 'Massimizza',
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
                _syncMaximizedState();
              },
            ),
            _WindowButton(
              icon: Icons.close,
              tooltip: 'Chiudi',
              hoverColor: Colors.redAccent,
              onPressed: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? hoverColor;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hoverColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        hoverColor: (hoverColor ?? Colors.black12).withValues(alpha: hoverColor != null ? 1.0 : 0.06),
        child: SizedBox(
          width: 46,
          height: 36,
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}
