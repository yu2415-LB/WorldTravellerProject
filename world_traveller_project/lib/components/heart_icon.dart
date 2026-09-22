import 'package:flutter/material.dart';

/// A heart drawn directly with a [Path], so it does not depend on the
/// Material Icons font. On the web build the font can lose glyphs (this is
/// why the "favourites" hearts were invisible); a painted heart is always
/// there, in light and dark theme, whatever the font does.
///
/// Takes its colour and size from the surrounding [IconTheme] (so it works
/// inside an [IconButton]) unless [color] / [size] are given.
class HeartIcon extends StatelessWidget {
  final bool filled;
  final double? size;
  final Color? color;

  const HeartIcon({super.key, this.filled = false, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24.0;
    final resolvedColor =
        color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;

    return SizedBox(
      width: resolvedSize,
      height: resolvedSize,
      child: CustomPaint(painter: _HeartPainter(resolvedColor, filled)),
    );
  }
}

class _HeartPainter extends CustomPainter {
  final Color color;
  final bool filled;

  const _HeartPainter(this.color, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.5, h * 0.88)
      ..cubicTo(w * 0.08, h * 0.60, w * 0.02, h * 0.32, w * 0.22, h * 0.17)
      ..cubicTo(w * 0.36, h * 0.06, w * 0.50, h * 0.16, w * 0.50, h * 0.28)
      ..cubicTo(w * 0.50, h * 0.16, w * 0.64, h * 0.06, w * 0.78, h * 0.17)
      ..cubicTo(w * 0.98, h * 0.32, w * 0.92, h * 0.60, w * 0.50, h * 0.88)
      ..close();

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    if (filled) {
      paint.style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    } else {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.10
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.color != color || old.filled != filled;
}
