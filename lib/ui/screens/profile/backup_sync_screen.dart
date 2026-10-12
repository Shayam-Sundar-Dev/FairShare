import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../data/database/database_helper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backup_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/people_provider.dart';
import '../auth/sign_in_screen.dart';
import '../auth/widgets/user_contact_setup_dialog.dart';

class BackupSyncScreen extends StatefulWidget {
  const BackupSyncScreen({super.key});

  @override
  State<BackupSyncScreen> createState() => _BackupSyncScreenState();
}

class _BackupSyncScreenState extends State<BackupSyncScreen> {
  bool _isDetailsExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BackupProvider>().refreshLiveCounts();
      }
    });
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays == 0) {
      return 'Today at ${DateFormat('h:mm a').format(dateTime)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${DateFormat('h:mm a').format(dateTime)}';
    } else {
      return DateFormat('MMM d, y • h:mm a').format(dateTime);
    }
  }

  Future<void> _handleBackup(BuildContext context) async {
    final backupProvider = context.read<BackupProvider>();
    final authProvider = context.read<AuthProvider>();

    if (authProvider.currentUser == null ||
        authProvider.currentUser!.isGuest ||
        authProvider.currentUser!.authProvider != 'google' ||
        !authProvider.isGoogleSessionActive) {
      final shouldConnect = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Connect Google Account'),
          content: const Text(
            'To backup and sync your information to your Google Account, please sign in with Google.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
              child: const Text('Sign in with Google'),
            ),
          ],
        ),
      );

      if (shouldConnect == true && context.mounted) {
        final success = await authProvider.signInWithGoogle();
        if (!success) return;
        if (context.mounted) {
          await UserContactSetupHelper.ensureContactDetails(
            context,
            forcePrompt: true,
            title: 'Google Profile Details',
            subtitle: 'Please enter your mobile number (mandatory) and UPI ID (optional) for your account.',
          );
        }
      } else {
        return;
      }
    }

    if (!context.mounted) return;
    final result = await backupProvider.backupNow();

    if (context.mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('✅ Cloud Backup successful! Synced to Google Drive.'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.shield_outlined, color: Color(0xFF10B981)),
                SizedBox(width: 10),
                Text('Backup Saved Locally', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Color(0xFF10B981), size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your data is safely backed up to your device.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  result.message ??
                      'Google Drive returned 403 Forbidden.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                const Text(
                  'To enable Google Drive Cloud Sync:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '1. Open Google Cloud Console\n'
                  '2. Go to APIs & Services > Library\n'
                  '3. Search for "Google Drive API" and click Enable\n'
                  '4. Make sure your OAuth screen allows Drive file access',
                  style:
                      TextStyle(fontSize: 12, height: 1.4, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  backupProvider.shareBackupFile();
                },
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Export File'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _handleRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cloud_download_outlined, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text('Restore from Cloud?'),
          ],
        ),
        content: const Text(
          'This will download and merge events, expenses, group members, settlements, and UPI IDs from your Google Drive backup into this device.\n\nExisting records will be safely updated without duplicates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore Now'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated ||
        authProvider.currentUser?.isGuest == true ||
        !authProvider.isGoogleSessionActive) {
      final shouldConnect = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.cloud_download_outlined, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('Google Sign-In Required'),
            ],
          ),
          content: const Text(
            'To restore your data from Google Drive, please sign in with the Google Account where your backup is saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
              child: const Text('Sign in with Google'),
            ),
          ],
        ),
      );

      if (shouldConnect == true && context.mounted) {
        final success = await authProvider.signInWithGoogle();
        if (!success) return;
        if (context.mounted) {
          await UserContactSetupHelper.ensureContactDetails(
            context,
            forcePrompt: true,
            title: 'Google Profile Details',
            subtitle: 'Please enter your mobile number (mandatory) and UPI ID (optional) for your account.',
          );
        }
      } else {
        return;
      }
    }

    if (!context.mounted) return;

    final backupProvider = context.read<BackupProvider>();
    final eventProvider = context.read<EventProvider>();
    final peopleProvider = context.read<PeopleProvider>();
    final categoryProvider = context.read<CategoryProvider>();

    final result = await backupProvider.restoreFromCloud(
      onRestored: () async {
        await eventProvider.loadEvents();
        await peopleProvider.initialize();
        await categoryProvider.loadCategories();
        await authProvider.initialize();
      },
    );

    if (context.mounted) {
      _showRestoreResultDialog(context, result);
    }
  }

  Future<void> _handleRestoreLocal(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.settings_backup_restore_rounded,
                color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('Restore Local Backup?'),
          ],
        ),
        content: const Text(
          'This will restore data from the local backup file saved on this device.\n\nExisting records will be merged without duplicates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore Local'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final backupProvider = context.read<BackupProvider>();
    final eventProvider = context.read<EventProvider>();
    final peopleProvider = context.read<PeopleProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final authProvider = context.read<AuthProvider>();

    final result = await backupProvider.restoreFromLocal(
      onRestored: () async {
        await eventProvider.loadEvents();
        await peopleProvider.initialize();
        await categoryProvider.loadCategories();
        await authProvider.initialize();
      },
    );

    if (context.mounted) {
      _showRestoreResultDialog(context, result);
    }
  }

  void _showRestoreResultDialog(BuildContext context, dynamic result) {
    if (result.success) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('Restore Successful'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('All data has been synchronized:'),
              const SizedBox(height: 12),
              if (result.restoredCounts != null)
                ...result.restoredCounts!.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          e.key.toString()[0].toUpperCase() +
                              e.key.toString().substring(1),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${e.value} items',
                          style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ ${result.message}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showBackupPayloadPreview(BuildContext context) async {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FutureBuilder<Map<String, dynamic>>(
        future: DatabaseHelper.instance.exportFullBackup(),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) {
            return Container(
              height: 300,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final data = snapshot.data!;
          final stats = data['stats'] as Map<String, dynamic>? ?? {};
          final userPrefs = data['user_preferences'] as Map<String, dynamic>? ?? {};

          return DraggableScrollableSheet(
            initialChildSize: 0.8,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            builder: (_, scrollController) => Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.preview_rounded,
                            color: Color(0xFF2563EB)),
                        const SizedBox(width: 10),
                        Text(
                          'Backup Payload Inspector',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          'SUMMARY METRICS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildStatChip(context, 'Trips', '${stats['events_count'] ?? 0}'),
                            _buildStatChip(context, 'People', '${stats['people_count'] ?? 0}'),
                            _buildStatChip(context, 'Expenses', '${stats['expenses_count'] ?? 0}'),
                            _buildStatChip(context, 'Splits', '${stats['splits_count'] ?? 0}'),
                            _buildStatChip(context, 'Settlements', '${stats['settlements_count'] ?? 0}'),
                            _buildStatChip(context, 'Milestones', '${stats['installments_count'] ?? 0}'),
                            _buildStatChip(context, 'Categories', '${stats['categories_count'] ?? 0}'),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (userPrefs.isNotEmpty) ...[
                          Text(
                            'ACCOUNT & USER PREFERENCES',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (userPrefs['user_phone_number'] != null || userPrefs['auth_phone_number'] != null)
                                  Text('• Personal Phone: ${userPrefs['user_phone_number'] ?? userPrefs['auth_phone_number']}',
                                      style: TextStyle(fontSize: 13, color: textPrimary)),
                                if (userPrefs['user_upi_id'] != null)
                                  Text('• Personal UPI ID: ${userPrefs['user_upi_id']}',
                                      style: TextStyle(fontSize: 13, color: textPrimary)),
                                if (userPrefs['theme_mode'] != null)
                                  Text('• Theme Preference: ${userPrefs['theme_mode']}',
                                      style: TextStyle(fontSize: 13, color: textPrimary)),
                                if (userPrefs['default_currency'] != null)
                                  Text('• Default Currency: ${userPrefs['default_currency']}',
                                      style: TextStyle(fontSize: 13, color: textPrimary)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        Text(
                          'RAW BACKUP JSON STRUCTURE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                          ),
                          child: SelectableText(
                            const JsonEncoder.withIndent('  ').convert({
                              'schema_version': data['schema_version'],
                              'app': data['app'],
                              'exported_at': data['exported_at'],
                              'stats': data['stats'],
                              'user_preferences': data['user_preferences'],
                              'tables_summary': {
                                'people_count': (data['tables']?['people'] as List?)?.length ?? 0,
                                'events_count': (data['tables']?['events'] as List?)?.length ?? 0,
                                'expenses_count': (data['tables']?['expenses'] as List?)?.length ?? 0,
                                'splits_count': (data['tables']?['expense_splits'] as List?)?.length ?? 0,
                                'settlements_count': (data['tables']?['settlements'] as List?)?.length ?? 0,
                                'categories_count': (data['tables']?['categories'] as List?)?.length ?? 0,
                                'trip_installments_count': (data['tables']?['trip_installments'] as List?)?.length ?? 0,
                              },
                            }),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, String label, String value) {
    final textPrimary = AppTheme.textPrimary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFF2563EB).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFF2563EB).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textPrimary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final authProvider = context.watch<AuthProvider>();
    final backupProvider = context.watch<BackupProvider>();
    final user = authProvider.currentUser;
    final isGoogleConnected = user != null &&
        !user.isGuest &&
        user.authProvider == 'google' &&
        user.email.isNotEmpty;
    final liveCounts = backupProvider.liveCounts;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Backup & Google Sync',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Inspect Backup Data',
            icon: const Icon(Icons.data_object_rounded),
            onPressed: () => _showBackupPayloadPreview(context),
          ),
          IconButton(
            tooltip: 'Share Backup File',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => backupProvider.shareBackupFile(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Google Account Connection Card
          LiquidGlassContainer(
            padding: const EdgeInsets.all(18),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.cloud_sync_rounded,
                        color: Color(0xFF2563EB),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isGoogleConnected
                                ? user.displayName
                                : 'Google Account Sync',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isGoogleConnected
                                ? user.email
                                : 'Sign in with Google to enable cloud sync',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: isGoogleConnected
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isGoogleConnected ? 'Connected' : 'Offline',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isGoogleConnected
                              ? const Color(0xFF10B981)
                              : Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isGoogleConnected) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SignInScreen(isModal: true),
                          ),
                        );
                      },
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: const Text('Connect Google Account'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Status & Info Card
          LiquidGlassContainer(
            padding: const EdgeInsets.all(18),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BACKUP STATUS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                _buildInfoRow(
                  context,
                  Icons.schedule_rounded,
                  'Last Synced',
                  _formatDate(backupProvider.lastBackupTime),
                ),
                Divider(
                  height: 20,
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
                _buildInfoRow(
                  context,
                  Icons.storage_rounded,
                  'Backup Size',
                  _formatBytes(backupProvider.lastBackupSize),
                ),
                Divider(
                  height: 20,
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
                _buildInfoRow(
                  context,
                  Icons.save_rounded,
                  'Storage Target',
                  backupProvider.cloudBackupInfo != null
                      ? 'Google Drive & Local'
                      : (backupProvider.lastBackupTime != null
                          ? 'Local Storage (Device)'
                          : 'None'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // DATA DETAILS & COVERAGE SECTION
          LiquidGlassContainer(
            padding: const EdgeInsets.all(18),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.verified_rounded,
                          color: Color(0xFF10B981), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WHAT GETS BACKED UP',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                              color: textSecondary,
                            ),
                          ),
                          Text(
                            'All end-user details are fully protected',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showBackupPayloadPreview(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Inspect', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Live data metrics grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.3,
                  children: [
                    _buildCoverageTile(
                      context,
                      icon: Icons.flight_takeoff_rounded,
                      color: const Color(0xFF3B82F6),
                      title: 'Trips & Plans',
                      countText: '${liveCounts['events'] ?? 0} Trips',
                    ),
                    _buildCoverageTile(
                      context,
                      icon: Icons.people_alt_rounded,
                      color: const Color(0xFF8B5CF6),
                      title: 'Members & Contacts',
                      countText: '${liveCounts['people'] ?? 0} People',
                    ),
                    _buildCoverageTile(
                      context,
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xFFF59E0B),
                      title: 'Expenses & Splits',
                      countText: '${liveCounts['expenses'] ?? 0} Bills',
                    ),
                    _buildCoverageTile(
                      context,
                      icon: Icons.handshake_rounded,
                      color: const Color(0xFF10B981),
                      title: 'Settlements',
                      countText: '${liveCounts['settlements'] ?? 0} Records',
                    ),
                    _buildCoverageTile(
                      context,
                      icon: Icons.account_balance_rounded,
                      color: const Color(0xFF06B6D4),
                      title: 'Committee Fund',
                      countText: '${liveCounts['installments'] ?? 0} Milestones',
                    ),
                    _buildCoverageTile(
                      context,
                      icon: Icons.category_rounded,
                      color: const Color(0xFFEC4899),
                      title: 'Categories',
                      countText: '${liveCounts['categories'] ?? 0} Types',
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(
                  height: 16,
                  color: isDark ? Colors.white10 : Colors.black12,
                ),

                // Expandable detailed breakdown of fields
                InkWell(
                  onTap: () {
                    setState(() {
                      _isDetailsExpanded = !_isDetailsExpanded;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _isDetailsExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: const Color(0xFF2563EB),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isDetailsExpanded
                              ? 'Hide Detailed Field List'
                              : 'Show All Backed Up Details & Fields',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_isDetailsExpanded) ...[
                  const SizedBox(height: 12),
                  _buildDetailItem(
                    context,
                    title: 'Trips & Events',
                    description:
                        'Trip titles, description, currency symbol, budgets, installment milestones, Drive share codes, and archive status.',
                  ),
                  _buildDetailItem(
                    context,
                    title: 'Phone Numbers, Members & UPI IDs',
                    description:
                        'Member phone numbers, personal account phone number, contact address book links, receiver UPI IDs, participant counts/weights, and avatar colors.',
                  ),
                  _buildDetailItem(
                    context,
                    title: 'Expenses & Bill Splits',
                    description:
                        'Expense titles, amounts, payers, date & time, category, exact split amounts/percentages, receipt attachments, GPS coordinates, and committee spend flags.',
                  ),
                  _buildDetailItem(
                    context,
                    title: 'Settlements & Settle-Up History',
                    description:
                        'Debtor & Creditor pairs, paid amounts, payment notes, and settlement completion timestamps.',
                  ),
                  _buildDetailItem(
                    context,
                    title: 'Committee Fund & Installments',
                    description:
                        'Installment milestones, member payment status (paid/unpaid), collected sums, paid dates, and installment notes.',
                  ),
                  _buildDetailItem(
                    context,
                    title: 'Categories & Preferences',
                    description:
                        'Custom and default spending categories (icons & colors), personal UPI ID, and app theme settings.',
                  ),
                ],
              ],
            ),
          ),

          if (backupProvider.errorMessage != null) ...[
            const SizedBox(height: 14),
            LiquidGlassContainer(
              padding: const EdgeInsets.all(14),
              borderRadius: BorderRadius.circular(16),
              borderColor: Colors.orange.withValues(alpha: 0.35),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: Colors.orange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cloud Sync Notice',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          backupProvider.errorMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Auto Sync Toggle
          LiquidGlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderRadius: BorderRadius.circular(18),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sync_rounded,
                    color: Color(0xFF10B981), size: 22),
              ),
              title: Text(
                'Auto-Sync on Changes',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              subtitle: Text(
                'Keep your group expenses, settlements, and UPI IDs synchronized in Google Drive',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
              value: backupProvider.autoSyncEnabled,
              activeThumbColor: const Color(0xFF10B981),
              onChanged: (val) => backupProvider.setAutoSync(val),
            ),
          ),
          const SizedBox(height: 24),

          // Primary Backup Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: backupProvider.isBusy
                  ? null
                  : () => _handleBackup(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              icon: backupProvider.isBackingUp
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
              label: Text(
                backupProvider.isBackingUp
                    ? 'Syncing to Google Drive...'
                    : 'Backup Now to Google Drive',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Restore Action Button (Cloud)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: backupProvider.isBusy
                  ? null
                  : () => _handleRestore(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
                side: const BorderSide(color: Color(0xFF3B82F6), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: backupProvider.isRestoring
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(Color(0xFF2563EB)),
                      ),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Text(
                backupProvider.isRestoring
                    ? 'Restoring Data...'
                    : 'Restore Data from Cloud',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Restore Action Button (Local)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: backupProvider.isBusy
                  ? null
                  : () => _handleRestoreLocal(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF10B981),
                side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.settings_backup_restore_rounded),
              label: const Text(
                'Restore from Local Device Backup',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Export JSON File Button
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => backupProvider.shareBackupFile(),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Export Offline Backup File (.json)'),
              style: TextButton.styleFrom(
                foregroundColor: textSecondary,
              ),
            ),
          ),

          const SizedBox(height: 16),
          // Privacy Info
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Your backup is stored securely in your private Google Drive.',
                  style: TextStyle(fontSize: 11.5, color: textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCoverageTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String countText,
  }) {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white10 : color.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  countText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(
    BuildContext context, {
    required String title,
    required String description,
  }) {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.check_circle_rounded,
                size: 14, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12.5, color: textSecondary, height: 1.35),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: textSecondary),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            color: textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
      ],
    );
  }
}
