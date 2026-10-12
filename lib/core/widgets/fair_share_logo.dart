import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'liquid_glass.dart';

/// An ultra-modern, vector-rendered brand logo for FairShare.
///
/// Symbolism:
/// - Interlocking fluid arcs symbolize equal, transparent sharing between friends.
/// - The dynamic dual-crescent geometry echoes a stylized percentage/division glyph
///   and an infinity loop of balance.
/// - Vibrant Cobalt Blue (#2563EB) and Emerald Mint (#10B981) gradients represent
///   financial clarity and trusted collaboration.
class FairShareLogo extends StatelessWidget {
  final double size;
  final bool showGlow;
  final bool useGlassContainer;

  const FairShareLogo({
    super.key,
    this.size = 48,
    this.showGlow = false,
    this.useGlassContainer = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget logo = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _FairShareLogoPainter(isDark: isDark),
      ),
    );

    if (showGlow) {
      logo = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.35 : 0.20),
              blurRadius: size * 0.4,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.15),
              blurRadius: size * 0.3,
              offset: Offset(size * 0.1, size * 0.1),
            ),
          ],
        ),
        child: logo,
      );
    }

    if (useGlassContainer) {
      return LiquidGlassContainer(
        width: size * 1.4,
        height: size * 1.4,
        borderRadius: BorderRadius.circular(size * 0.42),
        blur: 16,
        borderWidth: 1.2,
        child: Center(child: logo),
      );
    }

    return logo;
  }
}

class _FairShareLogoPainter extends CustomPainter {
  final bool isDark;

  const _FairShareLogoPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    // Gradient definitions
    final primaryGradient = SweepGradient(
      center: Alignment.center,
      startAngle: -math.pi / 2,
      endAngle: math.pi / 2,
      colors: const [
        Color(0xFF1D4ED8), // Deep Royal Blue
        Color(0xFF3B82F6), // Electric Cobalt
        Color(0xFF60A5FA), // Light Cobalt
      ],
    );

    final accentGradient = SweepGradient(
      center: Alignment.center,
      startAngle: math.pi / 2,
      endAngle: 3 * math.pi / 2,
      colors: const [
        Color(0xFF047857), // Deep Emerald
        Color(0xFF10B981), // Vivid Mint Teal
        Color(0xFF34D399), // Soft Mint
      ],
    );

    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track 1: Outer Primary Arc (Cobalt Blue - Represents User / Payer)
    final primaryPaint = Paint()
      ..shader = primaryGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.13
      ..strokeCap = StrokeCap.round;

    final arcRadius = radius * 0.72;
    final arcRect = Rect.fromCircle(center: center, radius: arcRadius);

    // Draw primary sweeping arc (-145° to +25°)
    canvas.drawArc(
      arcRect,
      -2.5,
      2.7,
      false,
      primaryPaint,
    );

    // Track 2: Outer Accent Arc (Emerald Teal - Represents Friend / Payee)
    final accentPaint = Paint()
      ..shader = accentGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.13
      ..strokeCap = StrokeCap.round;

    // Draw secondary sweeping arc (+35° to +205°)
    canvas.drawArc(
      arcRect,
      0.65,
      2.7,
      false,
      accentPaint,
    );

    // Dynamic S-Division Bridge / Connecting Wave
    final bridgePath = Path();
    final p1 = Offset(center.dx - radius * 0.35, center.dy - radius * 0.15);
    final p2 = Offset(center.dx + radius * 0.35, center.dy + radius * 0.15);
    bridgePath.moveTo(p1.dx, p1.dy);
    bridgePath.cubicTo(
      center.dx - radius * 0.1,
      center.dy + radius * 0.35,
      center.dx + radius * 0.1,
      center.dy - radius * 0.35,
      p2.dx,
      p2.dy,
    );

    final bridgePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3B82F6), Color(0xFF10B981)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(bridgePath, bridgePaint);

    // Node 1: Upper-Right Balance Dot (Cobalt Node)
    final node1Center = Offset(center.dx + radius * 0.28, center.dy - radius * 0.36);
    final node1Paint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF93C5FD), Color(0xFF2563EB)],
      ).createShader(Rect.fromCircle(center: node1Center, radius: radius * 0.14))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(node1Center, radius * 0.14, node1Paint);

    // Node 2: Lower-Left Balance Dot (Teal Node)
    final node2Center = Offset(center.dx - radius * 0.28, center.dy + radius * 0.36);
    final node2Paint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFA7F3D0), Color(0xFF059669)],
      ).createShader(Rect.fromCircle(center: node2Center, radius: radius * 0.14))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(node2Center, radius * 0.14, node2Paint);

    // Central Convergence Core (Soft Specular Glow Core)
    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.95 : 0.85)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.075, corePaint);
  }

  @override
  bool shouldRepaint(covariant _FairShareLogoPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
