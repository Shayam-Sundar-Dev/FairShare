import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backup_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/people_provider.dart';
import '../../providers/theme_provider.dart';
import '../auth/sign_in_screen.dart';
import '../auth/widgets/google_logo.dart';
import '../auth/widgets/user_contact_setup_dialog.dart';
import '../payments/widgets/host_upi_setup_dialog.dart';
import 'backup_sync_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isSigningIn = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isSigningIn = true);
    final authProvider = context.read<AuthProvider>();
    final peopleProvider = context.read<PeopleProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final success = await authProvider.signInWithGoogle();
      if (!mounted) return;

      if (success) {
        final user = authProvider.currentUser;
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

        messenger.showSnackBar(
          SnackBar(
            content: Text('Connected as ${user?.displayName ?? "User"}!'),
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

  void _confirmSignOut(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign Out?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        content: Text(
          'Are you sure you want to sign out? Your offline data will remain safely stored on this device.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary(context),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.slateMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final authProvider = context.read<AuthProvider>();
              final navigator = Navigator.of(context);
              await authProvider.signOut();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SignInScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.negativeRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _openUpiSetup(BuildContext context, {String? currentUpi}) async {
    final peopleProvider = context.read<PeopleProvider>();
    final initial = currentUpi ?? peopleProvider.selfPerson?.upiId;

    final result = await HostUpiSetupDialog.show(
      context,
      initialUpiId: initial,
      title: initial != null && initial.isNotEmpty ? 'Edit Host UPI ID' : 'Add & Verify UPI ID',
      subtitle: 'Enter the UPI ID where trip installments and settlement payments will be received via Google Pay.',
    );

    if (result != null && mounted) {
      await peopleProvider.updateSelfPerson(upiId: result);
      await peopleProvider.initialize();
      setState(() {});
    }
  }

  void _showRemoveUpiDialog(BuildContext context, String currentUpi) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.remove_circle_outline_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Remove UPI ID?'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "$currentUpi"? Friends will not be able to pay you directly via Google Pay until you add a new UPI ID.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.negativeRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final peopleProvider = context.read<PeopleProvider>();
              Navigator.of(ctx).pop();
              await HostUpiSetupDialog.saveHostUpiId('');
              await peopleProvider.updateSelfPerson(upiId: '');
              await peopleProvider.initialize();
              if (mounted) {
                setState(() {});
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('UPI ID removed'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showPhoneNumberSheet(BuildContext context, {required String currentPhone}) {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardBg = isDark ? const Color(0xFF111827) : Colors.white;

    final phoneController = TextEditingController(text: currentPhone);
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
                    width: 1.2,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SafeArea(
                top: false,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pull handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkBorderSubtle : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Header with Icon
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2563EB), Color(0xFF10B981)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.phone_iphone_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentPhone.isNotEmpty ? 'Edit Phone Number' : 'Add Phone Number',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Linked to your FairShare profile & splits',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your mobile number is used to identify your profile across shared expenses, receipt splits, and your friends roster.',
                        style: TextStyle(
                          fontSize: 13,
                          color: textSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Phone input field
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        autofocus: true,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                          letterSpacing: 0.5,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s\-\(\)]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Mobile Phone Number',
                          hintText: 'e.g. +91 98765 43210',
                          prefixIcon: Icon(Icons.phone_outlined, color: primaryColor),
                          suffixIcon: phoneController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    phoneController.clear();
                                    setSheetState(() {});
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: isDark
                              ? AppTheme.darkSurfaceElevated.withValues(alpha: 0.6)
                              : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: primaryColor, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a phone number';
                          }
                          final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
                          if (digitsOnly.length < 7) {
                            return 'Please enter a valid phone number (at least 7 digits)';
                          }
                          return null;
                        },
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      const SizedBox(height: 22),

                      // Action Buttons
                      Row(
                        children: [
                          if (currentPhone.isNotEmpty) ...[
                            OutlinedButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      setSheetState(() => isSaving = true);
                                      final authProvider = context.read<AuthProvider>();
                                      final peopleProvider = context.read<PeopleProvider>();
                                      final messenger = ScaffoldMessenger.of(context);

                                      await authProvider.updatePhoneNumber('');
                                      await peopleProvider.updateSelfPerson(phoneNumber: '');

                                      if (ctx.mounted) {
                                        Navigator.of(ctx).pop();
                                      }
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('Phone number removed'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.negativeRed,
                                side: BorderSide(
                                  color: AppTheme.negativeRed.withValues(alpha: 0.4),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: const Text('Remove'),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) return;
                                      setSheetState(() => isSaving = true);
                                      final trimmed = phoneController.text.trim();
                                      final authProvider = context.read<AuthProvider>();
                                      final peopleProvider = context.read<PeopleProvider>();
                                      final messenger = ScaffoldMessenger.of(context);

                                      await authProvider.updatePhoneNumber(trimmed);
                                      await peopleProvider.updateSelfPerson(phoneNumber: trimmed);

                                      if (ctx.mounted) {
                                        Navigator.of(ctx).pop();
                                      }
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('Phone number updated: $trimmed'),
                                          backgroundColor: AppTheme.positiveGreen,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(Colors.white),
                                      ),
                                    )
                                  : Text(
                                      currentPhone.isNotEmpty ? 'Save Changes' : 'Save Phone Number',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final backupProvider = context.watch<BackupProvider>();
    final eventProvider = context.watch<EventProvider>();
    final categoryProvider = context.watch<CategoryProvider>();
    final peopleProvider = context.watch<PeopleProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    final user = authProvider.currentUser;
    final selfPerson = peopleProvider.selfPerson;
    final userPhone = (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty)
        ? user.phoneNumber!
        : (selfPerson?.phoneNumber.isNotEmpty == true ? selfPerson!.phoneNumber : '');
    final userUpiId = selfPerson?.upiId ?? '';
    final isDemoUser = user != null && user.isDemo;
    final isGoogleUser = user != null && !user.isGuest && !user.isDemo;
    final isGoogleSessionActive = authProvider.isGoogleSessionActive;
    final displayName = user?.displayName.isNotEmpty == true
        ? user!.displayName
        : (isDemoUser ? 'Demo User' : 'Guest User');
    final email = user?.email.isNotEmpty == true
        ? user!.email
        : (isDemoUser ? 'demo@fairshare.app' : 'Guest Account (Offline)');

    final totalActive = eventProvider.activeEvents.length;
    final totalCompleted = eventProvider.archivedEvents.length;
    final totalPeople = peopleProvider.people.length;

    final borderColor = AppTheme.border(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('Account & Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          // Profile Liquid Glass Card
          LiquidGlassContainer(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(22),
            blur: 20,
            borderWidth: 1.2,
            child: Column(
              children: [
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (user?.photoUrl != null && user!.photoUrl!.isNotEmpty)
                          CircleAvatar(
                            radius: 32,
                            backgroundImage: NetworkImage(user.photoUrl!),
                          )
                        else
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: isDemoUser
                                ? Colors.amber.shade100
                                : primaryColor.withValues(alpha: 0.15),
                            child: Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isDemoUser
                                    ? Colors.amber.shade900
                                    : primaryColor,
                              ),
                            ),
                          ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              shape: BoxShape.circle,
                            ),
                            child: backupProvider.isBackingUp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation(Color(0xFF2563EB)),
                                    ),
                                  )
                                : Container(
                                    width: 16,
                                    height: 16,
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
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Status Badge
                              InkWell(
                                onTap: (isGoogleUser && !isGoogleSessionActive)
                                    ? () => _handleGoogleSignIn()
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (isGoogleUser && isGoogleSessionActive)
                                        ? (isDark ? const Color(0xFF14532D) : const Color(0xFFE8F5E9))
                                        : (isGoogleUser && !isGoogleSessionActive)
                                            ? (isDark ? const Color(0xFF78350F) : Colors.orange.shade50)
                                            : (isDemoUser
                                                ? (isDark ? const Color(0xFF78350F) : Colors.amber.shade50)
                                                : (isDark ? AppTheme.darkSurfaceElevated : const Color(0xFFF1F5F9))),
                                    borderRadius: BorderRadius.circular(8),
                                    border: (isGoogleUser && !isGoogleSessionActive)
                                        ? Border.all(color: Colors.orange.shade400, width: 1)
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        (isGoogleUser && isGoogleSessionActive)
                                            ? Icons.verified_rounded
                                            : (isGoogleUser && !isGoogleSessionActive)
                                                ? Icons.warning_amber_rounded
                                                : (isDemoUser ? Icons.star_rounded : Icons.person_outline_rounded),
                                        size: 13,
                                        color: (isGoogleUser && isGoogleSessionActive)
                                            ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32))
                                            : (isGoogleUser && !isGoogleSessionActive)
                                                ? (isDark ? Colors.orange.shade300 : Colors.orange.shade800)
                                                : (isDemoUser
                                                    ? (isDark ? Colors.amber.shade300 : Colors.amber.shade900)
                                                    : textSecondary),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        (isGoogleUser && isGoogleSessionActive)
                                            ? 'Google Verified'
                                            : (isGoogleUser && !isGoogleSessionActive)
                                                ? 'Reconnect Google'
                                                : (isDemoUser ? 'Demo Mode' : 'Guest Account'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: (isGoogleUser && isGoogleSessionActive)
                                              ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32))
                                              : (isGoogleUser && !isGoogleSessionActive)
                                                  ? (isDark ? Colors.orange.shade300 : Colors.orange.shade800)
                                                  : (isDemoUser
                                                      ? (isDark ? Colors.amber.shade300 : Colors.amber.shade900)
                                                      : textSecondary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Backup Status Pill
                              InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const BackupSyncScreen()),
                                  );
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: backupProvider.isFullyBackedUp
                                        ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.6) : const Color(0xFFECFDF5))
                                        : (isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade50),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: backupProvider.isFullyBackedUp
                                          ? (isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0))
                                          : Colors.orange.shade300,
                                      width: 0.8,
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
                                        size: 13,
                                        color: backupProvider.isFullyBackedUp
                                            ? const Color(0xFF10B981)
                                            : Colors.orange.shade800,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        backupProvider.isBackingUp
                                            ? 'Syncing...'
                                            : (backupProvider.isFullyBackedUp
                                                ? 'Backed Up'
                                                : 'Unbacked'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: backupProvider.isFullyBackedUp
                                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                              : Colors.orange.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Phone Number Pill
                              InkWell(
                                onTap: () => _showPhoneNumberSheet(context, currentPhone: userPhone),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: userPhone.isNotEmpty
                                        ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.6) : const Color(0xFFECFDF5))
                                        : (isDark ? primaryColor.withValues(alpha: 0.18) : primaryColor.withValues(alpha: 0.08)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: userPhone.isNotEmpty
                                          ? (isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0))
                                          : primaryColor.withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        userPhone.isNotEmpty ? Icons.phone_rounded : Icons.add_call,
                                        size: 12,
                                        color: userPhone.isNotEmpty
                                            ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                            : primaryColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        userPhone.isNotEmpty ? userPhone : 'Add Phone',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: userPhone.isNotEmpty
                                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                              : primaryColor,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(
                                        userPhone.isNotEmpty ? Icons.edit_rounded : Icons.add_rounded,
                                        size: 10,
                                        color: userPhone.isNotEmpty
                                            ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                            : primaryColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // UPI ID Pill
                              InkWell(
                                onTap: () => _openUpiSetup(context, currentUpi: userUpiId),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: userUpiId.isNotEmpty
                                        ? (isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.6) : const Color(0xFFEFF6FF))
                                        : (isDark ? primaryColor.withValues(alpha: 0.18) : primaryColor.withValues(alpha: 0.08)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: userUpiId.isNotEmpty
                                          ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFFBFDBFE))
                                          : primaryColor.withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        userUpiId.isNotEmpty ? Icons.account_balance_wallet_rounded : Icons.add_card_rounded,
                                        size: 12,
                                        color: userUpiId.isNotEmpty
                                            ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
                                            : primaryColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        userUpiId.isNotEmpty ? userUpiId : 'Add UPI ID',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: userUpiId.isNotEmpty
                                              ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
                                              : primaryColor,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(
                                        userUpiId.isNotEmpty ? Icons.verified_rounded : Icons.add_rounded,
                                        size: 10,
                                        color: userUpiId.isNotEmpty
                                            ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
                                            : primaryColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Google Connect Banner (if guest, demo, or if Google session needs reconnection)
          if (!isGoogleUser || !isGoogleSessionActive) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: (isGoogleUser && !isGoogleSessionActive)
                      ? [const Color(0xFF78350F), const Color(0xFF9A3412)]
                      : [const Color(0xFF0F172A), const Color(0xFF1E3A8A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: ((isGoogleUser && !isGoogleSessionActive)
                            ? const Color(0xFF78350F)
                            : const Color(0xFF0F172A))
                        .withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        (isGoogleUser && !isGoogleSessionActive)
                            ? Icons.warning_amber_rounded
                            : Icons.cloud_sync_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (isGoogleUser && !isGoogleSessionActive)
                            ? 'Google Connection Required'
                            : 'Link Google Account',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (isGoogleUser && !isGoogleSessionActive)
                        ? 'Your Google session has expired. Reconnect your Google account to sync trips and backup expenses to Google Drive.'
                        : 'Connect your Google Account to personalize receipts, profile avatar, and sync contacts seamlessly.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSigningIn ? null : () => _handleGoogleSignIn(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isSigningIn
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const GoogleLogo(size: 18),
                      label: Text(
                        (isGoogleUser && !isGoogleSessionActive)
                            ? 'Reconnect Google Account'
                            : 'Sign in with Google',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Quick Stats Grid with Liquid Glass Tiles
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context: context,
                  icon: Icons.bolt_rounded,
                  color: primaryColor,
                  label: 'Active',
                  value: '$totalActive',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  context: context,
                  icon: Icons.history_rounded,
                  color: AppTheme.positiveGreen,
                  label: 'Completed',
                  value: '$totalCompleted',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  context: context,
                  icon: Icons.people_alt_rounded,
                  color: AppTheme.accentColor,
                  label: 'Friends',
                  value: '$totalPeople',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // APPEARANCE & THEME SETTING
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  size: 16,
                  color: textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'APPEARANCE & THEME',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          LiquidGlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(20),
            blur: 18,
            borderWidth: 1.2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'App Theme',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            themeProvider.themeMode == ThemeMode.light
                                ? 'Light Mode active'
                                : themeProvider.themeMode == ThemeMode.dark
                                    ? 'Dark Mode active'
                                    : 'System Default active',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 3-way Liquid Glass Segmented Control
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkSurfaceElevated.withValues(alpha: 0.6) : const Color(0xFFF1F5F9).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? AppTheme.darkBorderUltraSubtle : AppTheme.borderSubtle,
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildThemeOption(
                        context: context,
                        mode: ThemeMode.light,
                        currentMode: themeProvider.themeMode,
                        title: 'Light',
                        icon: Icons.light_mode_rounded,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          themeProvider.setThemeMode(ThemeMode.light);
                        },
                      ),
                      _buildThemeOption(
                        context: context,
                        mode: ThemeMode.dark,
                        currentMode: themeProvider.themeMode,
                        title: 'Dark',
                        icon: Icons.dark_mode_rounded,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          themeProvider.setThemeMode(ThemeMode.dark);
                        },
                      ),
                      _buildThemeOption(
                        context: context,
                        mode: ThemeMode.system,
                        currentMode: themeProvider.themeMode,
                        title: 'System',
                        icon: Icons.brightness_auto_rounded,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          themeProvider.setThemeMode(ThemeMode.system);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Preferences & Info Liquid Glass Card
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'PREFERENCES & INFO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          LiquidGlassContainer(
            borderRadius: BorderRadius.circular(20),
            blur: 18,
            borderWidth: 1.2,
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (userPhone.isNotEmpty ? const Color(0xFF10B981) : primaryColor).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.phone_iphone_rounded,
                      color: userPhone.isNotEmpty ? const Color(0xFF10B981) : primaryColor,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Phone Number',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    userPhone.isNotEmpty ? userPhone : 'Tap to add your mobile number',
                    style: TextStyle(
                      fontSize: 12,
                      color: userPhone.isNotEmpty
                          ? textSecondary
                          : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
                      fontWeight: userPhone.isNotEmpty ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: userPhone.isNotEmpty
                              ? (isDark ? AppTheme.darkSurfaceElevated : const Color(0xFFF1F5F9))
                              : primaryColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: userPhone.isNotEmpty
                                ? (isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle)
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          userPhone.isNotEmpty ? 'Edit' : '+ Add',
                          style: TextStyle(
                            color: userPhone.isNotEmpty ? textPrimary : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 18, color: textSecondary),
                    ],
                  ),
                  onTap: () => _showPhoneNumberSheet(context, currentPhone: userPhone),
                ),
                Divider(color: borderColor.withValues(alpha: 0.6), height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (userUpiId.isNotEmpty ? const Color(0xFF2563EB) : primaryColor).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: userUpiId.isNotEmpty ? const Color(0xFF2563EB) : primaryColor,
                      size: 20,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        'Host UPI ID',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      if (userUpiId.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 10,
                                color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'VERIFIED',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    userUpiId.isNotEmpty
                        ? '$userUpiId • Google Pay / PhonePe'
                        : 'Add & verify UPI ID to receive settlement payments',
                    style: TextStyle(
                      fontSize: 12,
                      color: userUpiId.isNotEmpty
                          ? textSecondary
                          : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
                      fontWeight: userUpiId.isNotEmpty ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (userUpiId.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.negativeRed),
                          tooltip: 'Remove UPI ID',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showRemoveUpiDialog(context, userUpiId),
                        ),
                      if (userUpiId.isNotEmpty) const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: userUpiId.isNotEmpty
                              ? (isDark ? AppTheme.darkSurfaceElevated : const Color(0xFFF1F5F9))
                              : primaryColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: userUpiId.isNotEmpty
                                ? (isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle)
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          userUpiId.isNotEmpty ? 'Edit' : '+ Add',
                          style: TextStyle(
                            color: userUpiId.isNotEmpty ? textPrimary : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 18, color: textSecondary),
                    ],
                  ),
                  onTap: () => _openUpiSetup(context, currentUpi: userUpiId),
                ),
                Divider(color: borderColor.withValues(alpha: 0.6), height: 1),
                ListTile(
                  leading: Icon(
                    Icons.currency_rupee_rounded,
                    color: primaryColor,
                  ),
                  title: Text(
                    'Default Currency',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  trailing: Text(
                    '₹ INR',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textSecondary,
                    ),
                  ),
                ),
                Divider(color: borderColor.withValues(alpha: 0.6), height: 1),
                ListTile(
                  leading: const Icon(Icons.category_outlined, color: AppTheme.accentColor),
                  title: Text(
                    'Expense Categories',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  trailing: Text(
                    '${categoryProvider.expenseCategories.length} categories',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textSecondary,
                    ),
                  ),
                ),
                Divider(color: borderColor.withValues(alpha: 0.6), height: 1),
                Consumer<BackupProvider>(
                  builder: (context, backup, _) {
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: const Icon(Icons.cloud_sync_outlined, color: Color(0xFF2563EB)),
                        title: Text(
                          'Backup & Google Sync',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          backup.lastBackupTime != null
                              ? 'Cloud backup active'
                              : 'Backup data to Google Drive',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: textSecondary,
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BackupSyncScreen(),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                Divider(color: borderColor.withValues(alpha: 0.6), height: 1),
                ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: textSecondary),
                  title: Text(
                    'App Version',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  trailing: Text(
                    '1.0.0 (Build 1)',
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Sign Out Action
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.negativeRed,
                side: BorderSide(color: AppTheme.negativeRed.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sign Out from FairShare', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isSelected = mode == currentMode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppTheme.darkSurfaceElevated : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: isSelected
                ? Border.all(
                    color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
                    width: 0.9,
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? primaryColor
                    : (isDark ? AppTheme.darkTextSecondary : AppTheme.slateMuted),
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? primaryColor
                      : (isDark ? AppTheme.darkTextSecondary : AppTheme.slateMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);

    return LiquidGlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      borderRadius: BorderRadius.circular(14),
      blur: 12,
      borderWidth: 0.9,
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
