import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fair_share_logo.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../data/services/permission_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../auth/sign_in_screen.dart';
import '../auth/widgets/cloud_restore_prompt_dialog.dart';
import '../auth/widgets/user_contact_setup_dialog.dart';
import '../home/main_navigation_screen.dart';

class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({super.key});

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen>
    with WidgetsBindingObserver {
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh permission states when view loads, and auto-advance if all are already granted
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final onboarding = context.read<OnboardingProvider>();
      await onboarding.refreshPermissions();
      if (!mounted) return;
      if (onboarding.allPermissionsGranted ||
          onboarding.isOnboardingCompleted) {
        _proceedToLogin();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final onboarding = context.read<OnboardingProvider>();
      onboarding.refreshPermissions().then((_) {
        if (mounted && (onboarding.allPermissionsGranted || onboarding.isOnboardingCompleted)) {
          _proceedToLogin();
        }
      });
    }
  }

  void _proceedToLogin() async {
    if (_isNavigating || !mounted) return;

    // Ask phone number as mandatory and UPI-ID as optional on getting permission
    final contactSaved = await UserContactSetupHelper.ensureContactDetails(
      context,
      forcePrompt: true,
      title: 'Profile Setup',
      subtitle: 'Please enter your mobile number (mandatory) and UPI ID (optional) for trip collaboration.',
    );
    if (!contactSaved || !mounted) return;

    _isNavigating = true;

    final onboarding = context.read<OnboardingProvider>();
    final auth = context.read<AuthProvider>();
    await onboarding.completeOnboarding();
    if (mounted) {
      if (auth.currentUser != null && !auth.currentUser!.isGuest) {
        // Check for cloud backup and prompt restore if found
        await CloudRestoreHelper.checkAndPromptCloudRestore(context);
      }

      if (!mounted) return;
      final target = auth.currentUser != null
          ? const MainNavigationScreen()
          : const SignInScreen();

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, animation, _) => FadeTransition(
            opacity: animation,
            child: target,
          ),
        ),
      );
    }
  }

  void _handleGrantAllOrContinue() async {
    final onboarding = context.read<OnboardingProvider>();
    if (onboarding.allPermissionsGranted) {
      _proceedToLogin();
    } else {
      await onboarding.requestAllPermissions();
      if (mounted) {
        // If granted or completed round of requests, advance smoothly
        _proceedToLogin();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final onboarding = context.watch<OnboardingProvider>();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Ambient Fluid Gradient Blobs
          Positioned(
            top: -60,
            left: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF2563EB).withValues(alpha: isDark ? 0.30 : 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 240,
            right: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF10B981).withValues(alpha: isDark ? 0.22 : 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Scrollable Content
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 12),

                        // Modern App Brand Hero
                        const FairShareLogo(
                          size: 78,
                          showGlow: true,
                          useGlassContainer: true,
                        ),
                        const SizedBox(height: 20),

                        // Welcome Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B).withValues(alpha: 0.8)
                                : const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'WELCOME TO FAIRSHARE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: Color(0xFF3B82F6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Title & Slogan
                        Text(
                          'Split Bills & Expenses',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Before getting started, allow device permissions to enable automatic receipt capture, contact invites, and location tagging.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Progress Pill
                        LiquidGlassContainer(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          borderRadius: BorderRadius.circular(16),
                          child: Row(
                            children: [
                              Icon(
                                onboarding.allPermissionsGranted
                                    ? Icons.verified_rounded
                                    : Icons.security_rounded,
                                color: onboarding.allPermissionsGranted
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF3B82F6),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  onboarding.allPermissionsGranted
                                      ? 'All permissions active and ready'
                                      : 'Device Access (${onboarding.grantedCount}/${onboarding.totalCount} granted)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: onboarding.allPermissionsGranted
                                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                      : const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  onboarding.allPermissionsGranted
                                      ? 'Ready'
                                      : '${((onboarding.grantedCount / onboarding.totalCount) * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: onboarding.allPermissionsGranted
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF3B82F6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Permission Item 1: Contacts
                        _buildPermissionCard(
                          context: context,
                          icon: Icons.contacts_rounded,
                          iconColor: const Color(0xFF2563EB),
                          title: 'Contacts Access',
                          subtitle:
                              'Quickly pick friends and event members directly without typing phone numbers.',
                          isGranted: onboarding
                                  .permissionStatus[AppPermissionItem.contacts] ??
                              false,
                          isRequesting: onboarding.isRequestingAll,
                          onTap: () => onboarding
                              .requestPermission(AppPermissionItem.contacts),
                        ),
                        const SizedBox(height: 10),

                        // Permission Item 2: Camera
                        _buildPermissionCard(
                          context: context,
                          icon: Icons.camera_alt_rounded,
                          iconColor: const Color(0xFF10B981),
                          title: 'Camera Access',
                          subtitle:
                              'Snap instant photos of paper receipts, invoices, and physical restaurant bills.',
                          isGranted: onboarding
                                  .permissionStatus[AppPermissionItem.camera] ??
                              false,
                          isRequesting: onboarding.isRequestingAll,
                          onTap: () => onboarding
                              .requestPermission(AppPermissionItem.camera),
                        ),
                        const SizedBox(height: 10),

                        // Permission Item 3: Photos & Gallery
                        _buildPermissionCard(
                          context: context,
                          icon: Icons.photo_library_rounded,
                          iconColor: const Color(0xFF8B5CF6),
                          title: 'Photo & Media Library',
                          subtitle:
                              'Upload digital invoices, payment screenshots, and saved receipts from your gallery.',
                          isGranted: onboarding
                                  .permissionStatus[AppPermissionItem.photos] ??
                              false,
                          isRequesting: onboarding.isRequestingAll,
                          onTap: () => onboarding
                              .requestPermission(AppPermissionItem.photos),
                        ),
                        const SizedBox(height: 10),

                        // Permission Item 4: Location
                        _buildPermissionCard(
                          context: context,
                          icon: Icons.location_on_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          title: 'Location Tagging',
                          subtitle:
                              'Automatically detect venue names, cafes, and cities where expenses took place.',
                          isGranted: onboarding
                                  .permissionStatus[AppPermissionItem.location] ??
                              false,
                          isRequesting: onboarding.isRequestingAll,
                          onTap: () => onboarding
                              .requestPermission(AppPermissionItem.location),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Bottom Action Container
                LiquidGlassContainer(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Primary Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: onboarding.isRequestingAll
                              ? null
                              : _handleGrantAllOrContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: onboarding.isRequestingAll
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Requesting Permissions...',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      onboarding.allPermissionsGranted
                                          ? 'Continue to Login'
                                          : 'Grant All & Continue',
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward_rounded, size: 19),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Skip Button & Privacy Note
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _proceedToLogin,
                            style: TextButton.styleFrom(
                              foregroundColor: textSecondary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                            ),
                            child: const Text(
                              'Skip for now & Continue',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Privacy badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: textSecondary.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Permissions are used strictly on-device for expense tracking.',
                            style: TextStyle(
                              fontSize: 11,
                              color: textSecondary.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isGranted,
    required bool isRequesting,
    required VoidCallback onTap,
  }) {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: isGranted || isRequesting ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1E293B).withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isGranted
                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06)),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isGranted
                  ? const Color(0xFF10B981).withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon Pill
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),

            // Texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Status or Action Button
            if (isGranted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Granted',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              )
            else
              ElevatedButton(
                onPressed: isRequesting ? null : onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFEFF6FF),
                  foregroundColor: const Color(0xFF2563EB),
                  elevation: 0,
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                    ),
                  ),
                ),
                child: const Text(
                  'Allow',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
