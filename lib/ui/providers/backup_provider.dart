import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database/database_helper.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/google_drive_backup_service.dart';

class BackupProvider extends ChangeNotifier {
  final DatabaseHelper _databaseHelper;
  final GoogleDriveBackupService _backupService;
  final AuthService _authService;

  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _isLoadingInfo = false;
  DateTime? _lastBackupTime;
  int? _lastBackupSize;
  bool _autoSyncEnabled = false;
  CloudBackupMetadata? _cloudBackupInfo;
  String? _statusMessage;
  String? _errorMessage;
  Map<String, dynamic>? _lastStats;
  Map<String, int> _liveCounts = {};

  BackupProvider({
    DatabaseHelper? databaseHelper,
    GoogleDriveBackupService? backupService,
    AuthService? authService,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _backupService = backupService ?? GoogleDriveBackupService(),
        _authService = authService ?? AuthService() {
    initialize();
  }

  bool get isBackingUp => _isBackingUp;
  bool get isRestoring => _isRestoring;
  bool get isLoadingInfo => _isLoadingInfo;
  bool get isBusy => _isBackingUp || _isRestoring;
  DateTime? get lastBackupTime => _lastBackupTime;
  int? get lastBackupSize => _lastBackupSize;
  bool get autoSyncEnabled => _autoSyncEnabled;
  CloudBackupMetadata? get cloudBackupInfo => _cloudBackupInfo;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get lastStats => _lastStats;
  Map<String, int> get liveCounts => _liveCounts;
  bool get isFullyBackedUp =>
      (_cloudBackupInfo != null || _lastBackupTime != null) &&
      _errorMessage == null;

  Future<void> refreshLiveCounts() async {
    try {
      _liveCounts = await _databaseHelper.getDatabaseItemCounts();
      notifyListeners();
    } catch (e) {
      debugPrint('BackupProvider: error refreshing live counts: $e');
    }
  }

  Future<void> initialize() async {
    _isLoadingInfo = true;
    notifyListeners();

    try {
      _lastBackupTime = await _backupService.getLastBackupTime();
      _lastBackupSize = await _backupService.getLastBackupSize();
      _autoSyncEnabled = await _backupService.isAutoSyncEnabled();
      _liveCounts = await _databaseHelper.getDatabaseItemCounts();

      // Check if user is signed into Google, and query remote file
      final headers = await _authService.getAuthHeaders();
      if (headers != null) {
        _cloudBackupInfo = await _backupService.findCloudBackup();
        if (_cloudBackupInfo != null) {
          _lastBackupTime = _cloudBackupInfo!.modifiedTime;
          _lastBackupSize = _cloudBackupInfo!.sizeBytes;
        }
      }
    } catch (e) {
      debugPrint('BackupProvider: error initializing: $e');
    } finally {
      _isLoadingInfo = false;
      notifyListeners();
    }
  }

  /// Search Google Drive for an existing cloud backup and update local metadata.
  Future<CloudBackupMetadata?> checkForCloudBackup() async {
    try {
      final info = await _backupService.findCloudBackup(ensureScope: true);
      _cloudBackupInfo = info;
      if (info != null) {
        _lastBackupTime = info.modifiedTime;
        _lastBackupSize = info.sizeBytes;
      }
      notifyListeners();
      return info;
    } catch (e) {
      debugPrint('BackupProvider: error in checkForCloudBackup: $e');
      return null;
    }
  }

  /// Perform a full database backup and sync to the user's Google Account.
  Future<BackupResult> backupNow() async {
    if (_isBackingUp || _isRestoring) {
      return const BackupResult(success: false, message: 'Operation in progress');
    }

    _isBackingUp = true;
    _errorMessage = null;
    _statusMessage = 'Exporting local database...';
    notifyListeners();

    try {
      final backupData = await _databaseHelper.exportFullBackup();
      _lastStats = backupData['stats'] as Map<String, dynamic>?;

      _statusMessage = 'Uploading to Google Drive...';
      notifyListeners();

      final result =
          await _backupService.uploadBackupToGoogleDrive(backupData);

      _lastBackupTime = result.backupTime ?? DateTime.now();
      _lastBackupSize = result.sizeBytes;
      _liveCounts = await _databaseHelper.getDatabaseItemCounts();

      if (result.success) {
        _statusMessage = 'Backup completed successfully.';
        _cloudBackupInfo = await _backupService.findCloudBackup();
        _errorMessage = null;
      } else {
        _errorMessage = result.message;
        _statusMessage = 'Saved safely to local device backup.';
      }

      return result;
    } catch (e) {
      _errorMessage = 'Backup error: $e';
      _statusMessage = 'Failed to backup.';
      return BackupResult(success: false, message: e.toString());
    } finally {
      _isBackingUp = false;
      notifyListeners();
    }
  }

  /// Download and restore cloud backup data into local SQLite database.
  Future<RestoreResult> restoreFromCloud({
    required Future<void> Function() onRestored,
  }) async {
    if (_isRestoring || _isBackingUp) {
      return const RestoreResult(
          success: false, message: 'Operation in progress');
    }

    _isRestoring = true;
    _errorMessage = null;
    _statusMessage = 'Checking for Google Drive backup...';
    notifyListeners();

    try {
      var backupData = await _backupService.downloadCloudBackup();

      if (backupData == null) {
        _statusMessage = 'Checking local backup cache...';
        notifyListeners();
        backupData = await _backupService.getLocalBackup();
      }

      if (backupData == null) {
        _errorMessage = 'No backup file found in Google Drive or local storage.';
        return RestoreResult(
          success: false,
          message: _errorMessage!,
        );
      }

      _statusMessage = 'Restoring events, expenses & contacts...';
      notifyListeners();

      final restoredStats = await _databaseHelper.restoreFullBackup(backupData);
      _liveCounts = await _databaseHelper.getDatabaseItemCounts();

      _cloudBackupInfo = await _backupService.findCloudBackup();
      if (_cloudBackupInfo != null) {
        _lastBackupTime = _cloudBackupInfo!.modifiedTime;
        _lastBackupSize = _cloudBackupInfo!.sizeBytes;
      }

      // Re-trigger all providers to fetch latest restored tables
      await onRestored();

      _statusMessage = 'Restore completed successfully!';
      return RestoreResult(
        success: true,
        message: 'Successfully restored all application data.',
        restoredCounts: restoredStats,
      );
    } catch (e) {
      _errorMessage = 'Restore failed: $e';
      return RestoreResult(
        success: false,
        message: e.toString(),
      );
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  /// Restore data directly from locally cached backup file
  Future<RestoreResult> restoreFromLocal({
    required Future<void> Function() onRestored,
  }) async {
    if (_isRestoring || _isBackingUp) {
      return const RestoreResult(
          success: false, message: 'Operation in progress');
    }

    _isRestoring = true;
    _errorMessage = null;
    _statusMessage = 'Reading local backup file...';
    notifyListeners();

    try {
      final backupData = await _backupService.getLocalBackup();

      if (backupData == null) {
        _errorMessage = 'No local backup file found on this device.';
        return RestoreResult(
          success: false,
          message: _errorMessage!,
        );
      }

      _statusMessage = 'Restoring events, expenses & contacts...';
      notifyListeners();

      final restoredStats = await _databaseHelper.restoreFullBackup(backupData);
      _liveCounts = await _databaseHelper.getDatabaseItemCounts();
      await onRestored();

      _statusMessage = 'Restore completed successfully!';
      return RestoreResult(
        success: true,
        message: 'Successfully restored all application data from local backup.',
        restoredCounts: restoredStats,
      );
    } catch (e) {
      _errorMessage = 'Restore failed: $e';
      return RestoreResult(
        success: false,
        message: e.toString(),
      );
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  /// Export the full backup as a shareable JSON file using system share sheet.
  Future<bool> shareBackupFile() async {
    try {
      final backupData = await _databaseHelper.exportFullBackup();
      final filePath =
          await _backupService.exportToShareableFile(backupData);
      if (filePath == null) return false;

      final xFile = XFile(filePath);
      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          subject: 'FairShare Backup - ${DateTime.now().toLocal().toString().split('.').first}',
          text: 'FairShare App Data Backup',
        ),
      );
      return true;
    } catch (e) {
      debugPrint('BackupProvider: error sharing backup: $e');
      return false;
    }
  }

  /// Toggle automated backup setting
  Future<void> setAutoSync(bool enabled) async {
    _autoSyncEnabled = enabled;
    notifyListeners();
    await _backupService.setAutoSyncEnabled(enabled);
    if (enabled) {
      // Trigger background sync when enabled
      backupNow();
    }
  }
}
