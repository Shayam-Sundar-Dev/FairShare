import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/deep_link_handler.dart';
import '../../../core/widgets/fair_share_app_icon.dart';
import '../../providers/auth_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../auth/sign_in_screen.dart';
import '../home/main_navigation_screen.dart';
import '../onboarding/get_started_screen.dart';

/// Animated Launch Splash Screen that plays an elegant brand entrance
/// animation adapting to light and dark themes before opening the app.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _glowController;
  late final AnimationController _textController;

  late final Animation<double> _scaleAnimation;
  late final Animation<double> _rotationAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _glowAnimation;
  late final Animation<double> _textFadeAnimation;
  late final Animation<Offset> _textSlideAnimation;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // 1. Logo entrance controller (Scale, Rotate, Fade)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutBack),
      ),
    );

    _rotationAnimation = Tween<double>(begin: -0.35, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );

    // 2. Continuous breathing glow pulse
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.85, end: 1.18).animate(
      CurvedAnimation(
        parent: _glowController,
        curve: Curves.easeInOut,
      ),
    );

    // 3. Text entrance controller
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeIn,
      ),
    );

    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Start logo animation, then trigger text
    _logoController.forward().then((_) {
      if (mounted) {
        _textController.forward();
      }
    });

    // Schedule navigation after animation completes
    _scheduleNavigation();
  }

  void _scheduleNavigation() {
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted || _hasNavigated) return;
      _proceedToApp();
    });
  }

  Future<void> _proceedToApp() async {
    if (_hasNavigated || !mounted) return;

    final auth = context.read<AuthProvider>();
    final onboarding = context.read<OnboardingProvider>();

    // Ensure async initialization has completed, with a max safety timeout
    final timeout = DateTime.now().add(const Duration(milliseconds: 3500));
    while (mounted &&
        ((auth.isLoading && !auth.isInitialized) || onboarding.isLoading) &&
        DateTime.now().isBefore(timeout)) {
      await Future.delayed(const Duration(milliseconds: 80));
    }

    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;

    // If permissions are already granted, ensure onboarding is marked completed
    if (onboarding.allPermissionsGranted) {
      await onboarding.completeOnboarding();
    }

    Widget targetScreen;
    if (!onboarding.isOnboardingCompleted && !onboarding.allPermissionsGranted) {
      // First-time or fresh install after clear data / reinstall
      targetScreen = const GetStartedScreen();
    } else if (auth.currentUser != null) {
      targetScreen = const MainNavigationScreen();
    } else {
      targetScreen = const SignInScreen();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );

    // Notify deep link handler that app has transitioned to the target screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkHandler().markAppReady();
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _glowController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Ambient liquid background glowing blooms
          Positioned(
            top: -120,
            left: -80,
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, _) => Container(
                width: 320 * _glowAnimation.value,
                height: 320 * _glowAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF2563EB).withValues(alpha: isDark ? 0.28 : 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -80,
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, _) => Container(
                width: 300 * _glowAnimation.value,
                height: 300 * _glowAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF10B981).withValues(alpha: isDark ? 0.24 : 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Central Animated Brand Showcase
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Logo without Background (Large & Prominent)
                AnimatedBuilder(
                  animation: Listenable.merge([_logoController, _glowController]),
                  builder: (context, _) {
                    return Transform.rotate(
                      angle: _rotationAnimation.value,
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Opacity(
                          opacity: _fadeAnimation.value,
                          child: FairShareAppIcon(
                            size: 165,
                            isDark: isDark,
                            isCircle: false,
                            showBackground: false,
                            showGlow: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),

                // Animated App Name & Tagline
                SlideTransition(
                  position: _textSlideAnimation,
                  child: FadeTransition(
                    opacity: _textFadeAnimation,
                    child: Column(
                      children: [
                        // Shimmering Gradient Brand Name
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFF2563EB), // Electric Blue
                              Color(0xFF10B981), // Emerald Mint
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            'FairShare',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Split with ease • Fair & clear',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Minimal Loading Indicator at bottom
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _textFadeAnimation,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(
                      isDark ? const Color(0xFF38BDF8) : const Color(0xFF2563EB),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
