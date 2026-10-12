import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/sync_time_formatter.dart';
import '../../../../data/services/google_drive_backup_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/backup_provider.dart';
import '../../../providers/category_provider.dart';
import '../../../providers/event_provider.dart';
import '../../../providers/people_provider.dart';

/// Interactive modal dialog that asks the user if they wish to restore
/// an existing Google Drive backup found after signing in or during onboarding.
class CloudRestorePromptDialog extends StatelessWidget {
  final CloudBackupMetadata metadata;
  final String? email;

  const CloudRestorePromptDialog({
    super.key,
    required this.metadata,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final cardBg = AppTheme.cardBg(context);
    final borderColor = AppTheme.border(context);

    final timeStr = DateFormat('MMM d, yyyy · h:mm a').format(metadata.modifiedTime);
    final relativeStr = SyncTimeFormatter.formatRelative(metadata.modifiedTime);
    final sizeStr = metadata.sizeBytes > 0
        ? '${(metadata.sizeBytes / 1024).toStringAsFixed(1)} KB'
        : 'Cloud File';

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor, width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Gradient Icon
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.cloud_download_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cloud Backup Found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Google Drive Backup Available',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            Text(
              'We found an existing FairShare backup for your Google account. Would you like to restore your trips, expenses, friends, and settlements to this device?',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // Backup Metadata Preview Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Column(
                children: [
                  if (email != null && email!.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.account_circle_outlined,
                          size: 16,
                          color: Color(0xFF3B82F6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            email!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: borderColor),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 15,
                            color: textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Last Backup',
                            style: TextStyle(fontSize: 12, color: textSecondary),
                          ),
                        ],
                      ),
                      Text(
                        '$timeStr ($relativeStr)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.folder_zip_outlined,
                            size: 15,
                            color: textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Backup Size',
                            style: TextStyle(fontSize: 12, color: textSecondary),
                          ),
                        ],
                      ),
                      Text(
                        sizeStr,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textSecondary,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Start Fresh',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.cloud_download_rounded, size: 18),
                    label: const Text(
                      'Restore Now',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper to check and prompt the user to restore their cloud backup.
class CloudRestoreHelper {
  /// Checks Google Drive for an existing cloud backup and prompts the user to restore it.
  /// Returns `true` if restored, `false` otherwise.
  static Future<bool> checkAndPromptCloudRestore(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.currentUser == null || auth.currentUser!.isGuest) {
      return false;
    }

    final backupProvider = context.read<BackupProvider>();
    final metadata = await backupProvider.checkForCloudBackup();
    if (metadata == null || !context.mounted) {
      return false;
    }

    // Prompt user with confirmation dialog
    final shouldRestore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CloudRestorePromptDialog(
        metadata: metadata,
        email: auth.currentUser?.email,
      ),
    );

    if (shouldRestore != true || !context.mounted) {
      return false;
    }

    // Show restoring progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                  ),
                ),
                SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Restoring Data...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Syncing trips, expenses & members from Google Drive',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final eventProvider = context.read<EventProvider>();
      final peopleProvider = context.read<PeopleProvider>();
      final categoryProvider = context.read<CategoryProvider>();

      final result = await backupProvider.restoreFromCloud(
        onRestored: () async {
          await eventProvider.loadEvents();
          await peopleProvider.initialize();
          await categoryProvider.loadCategories();
          await auth.initialize();
        },
      );

      // Pop progress dialog
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (context.mounted) {
        if (result.success) {
          final eventCount = result.restoredCounts?['events'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      eventCount > 0
                          ? 'Backup restored successfully! $eventCount trips recovered.'
                          : 'Backup restored successfully!',
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          return true;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message.isNotEmpty
                  ? result.message
                  : 'Failed to restore backup from cloud.'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      debugPrint('CloudRestoreHelper: error restoring backup: $e');
    }

    return false;
  }
}
