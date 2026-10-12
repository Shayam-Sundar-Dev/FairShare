import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/backup_provider.dart';
import '../../../providers/people_provider.dart';
import '../../profile/backup_sync_screen.dart';
import '../sign_in_screen.dart';
import 'google_logo.dart';
import 'user_contact_setup_dialog.dart';

class UserProfileSheet extends StatefulWidget {
  const UserProfileSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const UserProfileSheet(),
    );
  }

  @override
  State<UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<UserProfileSheet> {
  bool _isSigningIn = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final backupProvider = context.watch<BackupProvider>();
    final user = authProvider.currentUser;

    final isDemoUser = user != null && user.isDemo;
    final isGoogleUser = user != null && !user.isGuest && !user.isDemo;
    final displayName = user?.displayName.isNotEmpty == true
        ? user!.displayName
        : (isDemoUser ? 'Demo User' : 'Guest User');
    final email = user?.email.isNotEmpty == true
        ? user!.email
        : (isDemoUser ? 'demo@fairshare.app' : 'Guest Mode (Offline)');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = AppTheme.cardBg(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final borderColor = AppTheme.border(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkBorderSubtle : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // User Avatar with backup badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              if (user?.photoUrl != null && user!.photoUrl!.isNotEmpty)
                CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage(user.photoUrl!),
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                )
              else
                CircleAvatar(
                  radius: 40,
                  backgroundColor: isDemoUser
                      ? Colors.amber.shade100
                      : primaryColor.withValues(alpha: 0.15),
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isDemoUser ? Colors.amber.shade900 : primaryColor,
                    ),
                  ),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: cardBg,
                    shape: BoxShape.circle,
                  ),
                  child: backupProvider.isBackingUp
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Color(0xFF2563EB)),
                          ),
                        )
                      : Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: backupProvider.isFullyBackedUp
                                ? const Color(0xFF10B981)
                                : Colors.orange.shade800,
                          ),
                          child: Icon(
                            backupProvider.isFullyBackedUp
                                ? Icons.check
                                : Icons.priority_high_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // User Name
          Text(
            displayName,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),

          // User Email
          Text(
            email,
            style: TextStyle(
              fontSize: 14,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 10),

          // Backup Status Pill
          InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupSyncScreen()),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: backupProvider.isFullyBackedUp
                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: backupProvider.isFullyBackedUp
                      ? const Color(0xFF10B981).withValues(alpha: 0.3)
                      : Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    backupProvider.isBackingUp
                        ? Icons.sync_rounded
                        : (backupProvider.isFullyBackedUp
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_upload_outlined),
                    size: 14,
                    color: backupProvider.isFullyBackedUp
                        ? const Color(0xFF10B981)
                        : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    backupProvider.isBackingUp
                        ? 'Syncing to Cloud...'
                        : (backupProvider.isFullyBackedUp
                            ? 'All Details Backed Up'
                            : 'Backup Pending (Tap to Sync)'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: backupProvider.isFullyBackedUp
                          ? const Color(0xFF10B981)
                          : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Auth Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isGoogleUser
                  ? (isDark ? const Color(0xFF14532D) : Colors.blue.shade50)
                  : (isDemoUser
                      ? (isDark ? const Color(0xFF78350F) : Colors.amber.shade50)
                      : (isDark ? AppTheme.darkSurfaceElevated : Colors.grey.shade100)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isGoogleUser
                    ? (isDark ? const Color(0xFF4ADE80) : Colors.blue.shade200)
                    : (isDemoUser
                        ? (isDark ? Colors.amber.shade300 : Colors.amber.shade300)
                        : borderColor),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isGoogleUser) ...[
                  const GoogleLogo(size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Google Account',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF4ADE80) : Colors.blue.shade900,
                    ),
                  ),
                ] else if (isDemoUser) ...[
                  Icon(Icons.science_outlined, size: 15, color: isDark ? Colors.amber.shade300 : Colors.amber.shade900),
                  const SizedBox(width: 6),
                  Text(
                    'Demo Account',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.person_outline_rounded, size: 14, color: textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Guest Mode',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Actions
          if (isGoogleUser) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _handleSignOut(context, authProvider),
              ),
            ),
          ] else if (isDemoUser) ...[
            // Switch to real Google
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: _isSigningIn
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const GoogleLogo(size: 20),
                label: Text(
                  _isSigningIn ? 'Connecting to Google...' : 'Switch to Google Account',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppTheme.darkSurfaceElevated : Colors.white,
                  foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                  elevation: 1,
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSigningIn ? null : _handleGoogleSignIn,
              ),
            ),
            const SizedBox(height: 12),
            // Sign Out of Demo Account
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                label: const Text(
                  'Sign Out of Demo Account',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _handleSignOut(context, authProvider),
              ),
            ),
          ] else ...[
            // Guest mode actions
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: _isSigningIn
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const GoogleLogo(size: 20),
                label: Text(
                  _isSigningIn ? 'Connecting to Google...' : 'Sign In with Google',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppTheme.darkSurfaceElevated : Colors.white,
                  foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                  elevation: 1,
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSigningIn ? null : _handleGoogleSignIn,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.science_outlined, size: 18, color: Colors.amber),
                label: const Text(
                  'Try Demo Account',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.amber.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  final success = await authProvider.signInWithDemoAccount();
                  if (context.mounted && success) {
                    context.read<PeopleProvider>().initialize();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Switched to Demo Account!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                label: const Text(
                  'Exit Guest Mode',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _handleSignOut(context, authProvider),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isSigningIn = true);
    final authProvider = context.read<AuthProvider>();
    final peopleProvider = context.read<PeopleProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final success = await authProvider.signInWithGoogle();
      if (!mounted) return;

      if (success) {
        await peopleProvider.initialize();
        if (!mounted) return;

        // Ask phone number as mandatory and UPI-ID as optional after google sign-in
        await UserContactSetupHelper.ensureContactDetails(
          context,
          forcePrompt: true,
          title: 'Google Profile Details',
          subtitle: 'Please enter your mobile number (mandatory) and UPI ID (optional) for your account.',
        );
        if (!mounted) return;

        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Connected as ${authProvider.currentUser?.displayName ?? "User"}!'),
            backgroundColor: AppTheme.positiveGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (authProvider.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage!),
            backgroundColor: AppTheme.negativeRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  void _handleSignOut(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign Out?',
          style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: AppTheme.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary(context))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
              await authProvider.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SignInScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.negativeRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
