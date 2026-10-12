import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Renders the official FairShare App Icon supporting Light & Dark themes,
/// with or without background, and both Circle and Rounded Square geometries.
class FairShareAppIcon extends StatelessWidget {
  final double size;
  final bool? isDark;
  final bool isCircle;
  final bool showBackground;
  final bool showGlow;
  final double? borderWidth;
  final VoidCallback? onTap;

  const FairShareAppIcon({
    super.key,
    this.size = 80,
    this.isDark,
    this.isCircle = false,
    this.showBackground = false,
    this.showGlow = true,
    this.borderWidth,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIsDark =
        isDark ?? (Theme.of(context).brightness == Brightness.dark);
    final borderW = borderWidth ?? (size * 0.025);
    final cornerRadius = isCircle ? (size / 2) : (size * 0.22);

    Widget iconContent = CustomPaint(
      size: Size(size, size),
      painter: _FairShareAppIconPainter(
        isDark: effectiveIsDark,
        isCircle: isCircle,
        showBackground: showBackground,
        borderWidth: borderW,
      ),
    );

    if (showGlow) {
      iconContent = Container(
        decoration: BoxDecoration(
          shape: isCircle || !showBackground ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: (isCircle || !showBackground)
              ? null
              : BorderRadius.circular(cornerRadius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB)
                  .withValues(alpha: effectiveIsDark ? 0.35 : 0.20),
              blurRadius: size * 0.45,
              spreadRadius: size * 0.04,
              offset: Offset(0, size * 0.04),
            ),
            BoxShadow(
              color: const Color(0xFF10B981)
                  .withValues(alpha: effectiveIsDark ? 0.28 : 0.16),
              blurRadius: size * 0.38,
              offset: Offset(size * 0.04, size * 0.04),
            ),
          ],
        ),
        child: iconContent,
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: iconContent,
      );
    }

    return iconContent;
  }
}

class _FairShareAppIconPainter extends CustomPainter {
  final bool isDark;
  final bool isCircle;
  final bool showBackground;
  final double borderWidth;

  const _FairShareAppIconPainter({
    required this.isDark,
    required this.isCircle,
    required this.showBackground,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final rect = Rect.fromLTWH(0, 0, w, h);

    if (showBackground) {
      // 1. Clipping Path
      final Path clipPath = Path();
      if (isCircle) {
        clipPath.addOval(rect.deflate(borderWidth / 2));
      } else {
        clipPath.addRRect(
          RRect.fromRectAndRadius(
            rect.deflate(borderWidth / 2),
            Radius.circular(w * 0.22),
          ),
        );
      }

      canvas.save();
      canvas.clipPath(clipPath);

      // 2. Background Gradient
      final bgGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [
                Color(0xFF0F172A), // Deep Slate Navy
                Color(0xFF0B132B), // Obsidian Midnight
              ]
            : const [
                Color(0xFFFFFFFF), // Pure Crisp White
                Color(0xFFEEF4FF), // Frosted Icy Blue
              ],
      );

      final bgPaint = Paint()..shader = bgGradient.createShader(rect);
      canvas.drawRect(rect, bgPaint);

      // Subtle ambient radial glow
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF2563EB).withValues(alpha: isDark ? 0.35 : 0.18),
            const Color(0xFF10B981).withValues(alpha: isDark ? 0.20 : 0.10),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: w * 0.55));
      canvas.drawRect(rect, glowPaint);
    }

    // 3. Dual Interlocking Arcs
    // When showBackground is false, scale up the arcs to occupy full size
    final arcRadius = showBackground ? w * 0.26 : w * 0.38;
    final arcStroke = showBackground ? w * 0.088 : w * 0.125;
    final arcRect = Rect.fromCircle(center: center, radius: arcRadius);

    // Track 1: Cobalt Blue (Primary Payer Arc)
    final primaryGradient = SweepGradient(
      center: Alignment.center,
      startAngle: -math.pi / 2,
      endAngle: math.pi / 2,
      colors: const [
        Color(0xFF1D4ED8), // Royal Cobalt
        Color(0xFF2563EB), // Electric Blue
        Color(0xFF60A5FA), // Light Cobalt
      ],
    );

    final primaryPaint = Paint()
      ..shader = primaryGradient.createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcStroke
      ..strokeCap = StrokeCap.round;

    // Draw primary arc (-145° to +25°)
    canvas.drawArc(arcRect, -2.5, 2.7, false, primaryPaint);

    // Track 2: Emerald Mint (Secondary Payee Arc)
    final accentGradient = SweepGradient(
      center: Alignment.center,
      startAngle: math.pi / 2,
      endAngle: 3 * math.pi / 2,
      colors: const [
        Color(0xFF059669), // Deep Emerald
        Color(0xFF10B981), // Vivid Mint
        Color(0xFF34D399), // Soft Seafoam
      ],
    );

    final accentPaint = Paint()
      ..shader = accentGradient.createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcStroke
      ..strokeCap = StrokeCap.round;

    // Draw secondary arc (+35° to +205°)
    canvas.drawArc(arcRect, 0.65, 2.7, false, accentPaint);

    // 4. Connecting Fluid S-Wave (Equitable Division Bridge)
    final bridgePath = Path();
    final p1 = Offset(center.dx - arcRadius * 0.52, center.dy - arcRadius * 0.22);
    final p2 = Offset(center.dx + arcRadius * 0.52, center.dy + arcRadius * 0.22);
    bridgePath.moveTo(p1.dx, p1.dy);
    bridgePath.cubicTo(
      center.dx - arcRadius * 0.1,
      center.dy + arcRadius * 0.45,
      center.dx + arcRadius * 0.1,
      center.dy - arcRadius * 0.45,
      p2.dx,
      p2.dy,
    );

    final bridgePaint = Paint()
      ..color = isDark
          ? const Color(0xFFF8FAFC).withValues(alpha: 0.92)
          : const Color(0xFF1E293B).withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcStroke * 0.78
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(bridgePath, bridgePaint);

    // 5. Circular Division Nodes
    final nodeRadius = arcStroke * 0.52;

    // Top-right node (Cobalt Blue)
    final node1Center = Offset(center.dx + arcRadius * 0.42, center.dy - arcRadius * 0.62);
    final node1Paint = Paint()..color = const Color(0xFF3B82F6);
    canvas.drawCircle(node1Center, nodeRadius, node1Paint);

    // Bottom-left node (Emerald Mint)
    final node2Center = Offset(center.dx - arcRadius * 0.42, center.dy + arcRadius * 0.62);
    final node2Paint = Paint()..color = const Color(0xFF10B981);
    canvas.drawCircle(node2Center, nodeRadius, node2Paint);

    if (showBackground) {
      canvas.restore();

      // 6. Outer Border / Rim
      if (borderWidth > 0) {
        final borderPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = isDark
              ? Colors.white.withValues(alpha: 0.14)
              : const Color(0xFF2563EB).withValues(alpha: 0.22);

        if (isCircle) {
          canvas.drawOval(rect.deflate(borderWidth / 2), borderPaint);
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect.deflate(borderWidth / 2),
              Radius.circular(w * 0.22),
            ),
            borderPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FairShareAppIconPainter oldDelegate) {
    return oldDelegate.isDark != isDark ||
        oldDelegate.isCircle != isCircle ||
        oldDelegate.showBackground != showBackground ||
        oldDelegate.borderWidth != borderWidth;
  }
}
