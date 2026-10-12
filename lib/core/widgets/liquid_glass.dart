import 'dart:ui';
import 'package:flutter/material.dart';

/// A reusable widget that produces an authentic liquid glass / glassmorphic effect
/// with backdrop blur, specular border refraction, and translucent gradient fills.
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final BorderRadiusGeometry? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final Gradient? gradient;
  final List<BoxShadow>? shadows;
  final Clip clipBehavior;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.blur = 12.0,
    this.borderRadius,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.color,
    this.borderColor,
    this.borderWidth = 0.9,
    this.gradient,
    this.shadows,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(16);

    // Minimal subtle container fill with subtle light reflection
    final defaultGradient = gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1E293B).withValues(alpha: 0.75),
                  const Color(0xFF0F172A).withValues(alpha: 0.85),
                ]
              : [
                  Colors.white.withValues(alpha: 0.96),
                  const Color(0xFFF8FAFC).withValues(alpha: 0.90),
                ],
        );

    // Crisp micro border
    final defaultBorderColor = borderColor ??
        (isDark
            ? const Color(0xFF334155).withValues(alpha: 0.6)
            : const Color(0xFFE2E8F0));

    // Dual-layer soft elevation for authentic depth
    final defaultShadows = shadows ??
        [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: isDark
                ? const Color(0xFF38BDF8).withValues(alpha: 0.02)
                : const Color(0xFF2563EB).withValues(alpha: 0.015),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ];

    Widget current = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color != null ? color : (gradient == null ? null : null),
        gradient: color == null ? defaultGradient : null,
        borderRadius: radius,
        border: Border.all(
          color: defaultBorderColor,
          width: borderWidth,
        ),
      ),
      child: child,
    );

    // Apply backdrop filter if blur > 0
    if (blur > 0) {
      current = ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: current,
        ),
      );
    }

    // Apply shadow container
    if (defaultShadows.isNotEmpty) {
      current = Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: defaultShadows,
        ),
        child: current,
      );
    }

    if (margin != null) {
      current = Padding(padding: margin!, child: current);
    }

    return current;
  }
}

/// Minimal background with quiet ambient gradient
class LiquidGlassBackground extends StatelessWidget {
  final Widget child;

  const LiquidGlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Base background
        Positioned.fill(
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
        ),

        // Gentle ambient top accent
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: isDark
                    ? [
                        const Color(0xFF2563EB).withValues(alpha: 0.08),
                        Colors.transparent,
                      ]
                    : [
                        const Color(0xFF3B82F6).withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
              ),
            ),
          ),
        ),

        // Main content
        Positioned.fill(child: child),
      ],
    );
  }
}
