import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:world_traveller_project/services/fullscreen_service.dart';

class FullscreenImageView extends StatefulWidget {
  final String? imageUrl;
  final Uint8List? memoryBytes;
  final String? title;

  const FullscreenImageView({
    super.key,
    this.imageUrl,
    this.memoryBytes,
    this.title,
  });

  @override
  State<FullscreenImageView> createState() => _FullscreenImageViewState();
}

class _FullscreenImageViewState extends State<FullscreenImageView> {
  @override
  void initState() {
    super.initState();
    FullscreenService.enter();
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    FullscreenService.exit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) {
      imageWidget = Image.memory(
        widget.memoryBytes!,
        fit: BoxFit.contain,
      );
    } else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      imageWidget = Image.network(
        widget.imageUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
              SizedBox(height: 12),
              Text(
                'Could not load the picture',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    } else {
      imageWidget = const Center(
        child: Icon(Icons.image_not_supported, color: Colors.white54, size: 64),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 5.0,
              child: Center(
                child: imageWidget,
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: SafeArea(
                child: IconButton(
                  iconSize: 32,
                  tooltip: 'Chiudi (ESC)',
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                    ),
                  ),
                  onPressed: _close,
                ),
              ),
            ),
            if (widget.title != null && widget.title!.isNotEmpty)
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: SafeArea(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}