import 'package:intl/intl.dart';

class SyncTimeFormatter {
  /// Returns a human-friendly string for sync status, e.g. "Synced just now", "Synced 5m ago", "Synced Oct 5".
  static String formatSyncTime(DateTime? syncTime, {String fallback = 'Synced'}) {
    if (syncTime == null) return fallback;
    final now = DateTime.now();
    final diff = now.difference(syncTime);

    if (diff.isNegative || diff.inMinutes < 1) {
      return 'Synced just now';
    } else if (diff.inMinutes < 60) {
      return 'Synced ${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return 'Synced ${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Synced yesterday';
    } else if (diff.inDays < 7) {
      return 'Synced ${diff.inDays}d ago';
    } else {
      return 'Synced ${DateFormat('MMM d').format(syncTime)}';
    }
  }

  /// Returns a compact relative time string, e.g. "Just now", "5m ago", "Oct 5".
  static String formatRelative(DateTime? syncTime, {String fallback = 'Synced'}) {
    if (syncTime == null) return fallback;
    final now = DateTime.now();
    final diff = now.difference(syncTime);

    if (diff.isNegative || diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(syncTime);
    }
  }
}
