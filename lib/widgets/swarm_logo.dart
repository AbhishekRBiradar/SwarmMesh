import 'package:flutter/material.dart';

/// Uses the same Android launcher bitmap inside the Flutter UI so the product
/// has one recognizable mark from the device home screen through the app.
class SwarmLogo extends StatelessWidget {
  const SwarmLogo({super.key, this.size = 64});

  final double size;

  static const _asset =
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png';

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Draw immediately while the exact launcher bitmap is loading. This
        // prevents a blank/black intro frame on a cold Android start.
        CustomPaint(painter: _FallbackLogoPainter()),
        Image.asset(
          _asset,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ],
    ),
  );
}

class _FallbackLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide;
    final paint = Paint()..style = PaintingStyle.fill;
    Path polygon(List<Offset> points, Color color) {
      paint.color = color;
      return Path()
        ..addPolygon([
          for (final point in points)
            Offset(point.dx * scale, point.dy * scale),
        ], true)
        ..let((path) => canvas.drawPath(path, paint));
    }

    polygon(const [
      Offset(.55, .02),
      Offset(.96, .02),
      Offset(.27, .68),
      Offset(.08, .48),
    ], const Color(0xFF51BCE8));
    polygon(const [
      Offset(.48, .46),
      Offset(.96, .46),
      Offset(.52, .88),
      Offset(.30, .66),
    ], const Color(0xFF22A9E0));
    polygon(const [
      Offset(.52, .68),
      Offset(.96, .68),
      Offset(.65, .98),
      Offset(.30, .68),
    ], const Color(0xFF07518C));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension on Path {
  Path let(void Function(Path) action) {
    action(this);
    return this;
  }
}
