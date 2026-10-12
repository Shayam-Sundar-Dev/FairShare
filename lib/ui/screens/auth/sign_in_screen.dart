import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fair_share_logo.dart';
import '../../providers/auth_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/people_provider.dart';
import '../home/main_navigation_screen.dart';
import 'widgets/cloud_restore_prompt_dialog.dart';
import 'widgets/google_logo.dart';
import 'widgets/user_contact_setup_dialog.dart';

class SignInScreen extends StatelessWidget {
  final bool isModal;

  const SignInScreen({super.key, this.isModal = false});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final borderColor = AppTheme.border(context);
    final cardBg = AppTheme.cardBg(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: isModal
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App Logo and Brand
                const FairShareLogo(
                  size: 76,
                  showGlow: true,
                  useGlassContainer: true,
                ),
                const SizedBox(height: 22),

                Text(
                  'FairShare',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  'Split group expenses fairly, seamlessly, and transparently.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 36),

                // Feature Highlights
                _buildFeatureRow(
                  context,
                  Icons.calculate_outlined,
                  'Smart Debt Simplification',
                  'Minimizes number of transfers between friends.',
                ),
                const SizedBox(height: 14),
                _buildFeatureRow(
                  context,
                  Icons.receipt_long_outlined,
                  'Flexible Expense Splits',
                  'Split equally, exact amounts, percentages, or shares.',
                ),
                const SizedBox(height: 14),
                _buildFeatureRow(
                  context,
                  Icons.cloud_sync_outlined,
                  'Google Account Sync',
                  'Keep your name, identity, and events synced.',
                ),
                const SizedBox(height: 40),

                // Error Message if any
                if (authProvider.errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.negativeRed.withValues(alpha: 0.15)
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.negativeRed.withValues(alpha: 0.4)
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: isDark ? AppTheme.negativeRed : Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            authProvider.errorMessage!,
                            style: TextStyle(
                              color: isDark ? Colors.red.shade300 : Colors.red.shade800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Google Sign In / Sign Up Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: authProvider.isLoading
                        ? null
                        : () async {
                            final success = await authProvider.signInWithGoogle();
                            if (context.mounted) {
                              if (success) {
                                context.read<PeopleProvider>().initialize();
                                context.read<OnboardingProvider>().completeOnboarding();

                                // Ask phone number as mandatory and UPI-ID as optional after google sign-in
                                await UserContactSetupHelper.ensureContactDetails(
                                  context,
                                  forcePrompt: true,
                                  title: 'Profile Details',
                                  subtitle: 'Please enter your mobile number (mandatory) and UPI ID (optional) for your account.',
                                );

                                if (!context.mounted) return;

                                // Check for cloud backup and ask user whether to restore
                                await CloudRestoreHelper.checkAndPromptCloudRestore(context);

                                if (context.mounted) {
                                  if (isModal) {
                                    Navigator.pop(context);
                                  } else {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
                                    );
                                  }
                                }
                              } else if (authProvider.errorMessage != null) {
                                _showGoogleSignInErrorDialog(context, authProvider.errorMessage!);
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cardBg,
                      foregroundColor: textPrimary,
                      elevation: 1,
                      shadowColor: Colors.black.withValues(alpha: 0.1),
                      side: BorderSide(color: borderColor, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: authProvider.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const GoogleLogo(size: 22),
                              const SizedBox(width: 12),
                              Text(
                                'Continue with Google',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Guest Option (if not already in a modal)
                if (!isModal) ...[
                  Row(
                    children: [
                      Expanded(child: Divider(color: borderColor)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: borderColor)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: authProvider.isLoading
                          ? null
                          : () async {
                              await authProvider.signInAsGuest();
                              if (context.mounted) {
                                context.read<OnboardingProvider>().completeOnboarding();
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
                                );
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Continue as Guest',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton.icon(
                      icon: const Icon(Icons.science_outlined, size: 18, color: AppTheme.primaryColor),
                      label: const Text(
                        'Try with Demo Account',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      onPressed: authProvider.isLoading
                          ? null
                          : () async {
                              final success = await authProvider.signInWithDemoAccount();
                              if (context.mounted && success) {
                                context.read<PeopleProvider>().initialize();
                                context.read<OnboardingProvider>().completeOnboarding();
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
                                );
                              }
                            },
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                Text(
                  'By signing in, you agree to FairShare’s terms of service and privacy policy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(BuildContext context, IconData icon, String title, String subtitle) {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showGoogleSignInErrorDialog(BuildContext context, String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            GoogleLogo(size: 22),
            SizedBox(width: 10),
            Text('Google Sign-In'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.contains('ApiException: 10') || error.contains('DEVELOPER_ERROR')
                  ? 'Google Play Services returned a configuration notice (OAuth Client ID or SHA-1 fingerprint needs to be added in Google Cloud Console for package com.fairshare.fairshare).'
                  : 'Unable to complete Google Sign-In:\n$error',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Would you like to use a Demo Google Profile to test authenticated features right away?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final auth = context.read<AuthProvider>();
              final success = await auth.signInWithDemoAccount();
              if (success && context.mounted) {
                context.read<PeopleProvider>().initialize();
                if (isModal) {
                  Navigator.pop(context);
                } else {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
                  );
                }
              }
            },
            child: const Text('Use Demo Profile'),
          ),
        ],
      ),
    );
  }
}
