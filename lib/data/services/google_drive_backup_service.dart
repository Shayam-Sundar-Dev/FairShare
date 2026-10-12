import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class CloudBackupMetadata {
  final String fileId;
  final String fileName;
  final DateTime modifiedTime;
  final int sizeBytes;

  const CloudBackupMetadata({
    required this.fileId,
    required this.fileName,
    required this.modifiedTime,
    required this.sizeBytes,
  });
}

class BackupResult {
  final bool success;
  final String? message;
  final DateTime? backupTime;
  final int? sizeBytes;
  final Map<String, dynamic>? stats;
  final String? localFilePath;

  const BackupResult({
    required this.success,
    this.message,
    this.backupTime,
    this.sizeBytes,
    this.stats,
    this.localFilePath,
  });
}

class RestoreResult {
  final bool success;
  final String message;
  final DateTime? backupTime;
  final Map<String, int>? restoredCounts;

  const RestoreResult({
    required this.success,
    required this.message,
    this.backupTime,
    this.restoredCounts,
  });
}

class GoogleDriveBackupService {
  final AuthService _authService;
  static const String backupFileName = 'fairshare_backup.json';
  static const String _prefLastBackupTime = 'cloud_last_backup_time';
  static const String _prefLastBackupSize = 'cloud_last_backup_size';
  static const String _prefAutoSyncEnabled = 'cloud_auto_sync_enabled';

  GoogleDriveBackupService({AuthService? authService})
      : _authService = authService ?? AuthService();

  /// Retrieve the last saved backup time from local preferences
  Future<DateTime?> getLastBackupTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_prefLastBackupTime);
      if (str != null) return DateTime.tryParse(str);
    } catch (_) {}
    return null;
  }

  /// Retrieve the last saved backup size in bytes
  Future<int?> getLastBackupSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_prefLastBackupSize);
    } catch (_) {}
    return null;
  }

  /// Check whether automatic cloud sync is enabled
  Future<bool> isAutoSyncEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefAutoSyncEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Toggle automatic cloud sync
  Future<void> setAutoSyncEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefAutoSyncEnabled, enabled);
    } catch (_) {}
  }

  /// Search for an existing backup file in Google Drive
  Future<CloudBackupMetadata?> findCloudBackup({bool ensureScope = false}) async {
    try {
      if (ensureScope) {
        await _authService.ensureDriveScope();
      }
      final headers = await _authService.getAuthHeaders();
      if (headers == null) return null;

      final rootUri = Uri.https(
        'www.googleapis.com',
        '/drive/v3/files',
        {
          'q': "name = '$backupFileName' and trashed = false",
          'spaces': 'drive',
          'orderBy': 'modifiedTime desc',
          'pageSize': '10',
          'fields': 'files(id,name,modifiedTime,size)',
          'supportsAllDrives': 'true',
          'includeItemsFromAllDrives': 'true',
        },
      );

      final response = await http.get(rootUri, headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final files = data['files'] as List?;
        if (files != null && files.isNotEmpty) {
          for (final f in files) {
            final id = f['id']?.toString() ?? '';
            if (id.isNotEmpty) {
              return CloudBackupMetadata(
                fileId: id,
                fileName: f['name'] ?? backupFileName,
                modifiedTime: DateTime.tryParse(f['modifiedTime'] ?? '') ??
                    DateTime.now(),
                sizeBytes: int.tryParse(f['size']?.toString() ?? '0') ?? 0,
              );
            }
          }
        }
      } else {
        debugPrint(
            'GoogleDriveBackupService: findCloudBackup returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('GoogleDriveBackupService: error finding cloud backup: $e');
    }
    return null;
  }

  /// Upload the full database backup payload to Google Drive
  Future<BackupResult> uploadBackupToGoogleDrive(
      Map<String, dynamic> backupData) async {
    final now = DateTime.now();
    final jsonBytes = utf8.encode(jsonEncode(backupData));
    final sizeBytes = jsonBytes.length;

    // 1. Always save a local copy first to guarantee no data loss
    final localPath = await saveLocalBackup(backupData);

    try {
      // 2. Ensure Drive scope before retrieving authorization headers
      await _authService.ensureDriveScope();

      // 3. Fetch fresh headers with the granted scopes
      final headers = await _authService.getAuthHeaders();
      if (headers == null) {
        return BackupResult(
          success: false,
          message:
              'Google Account not signed in. Backup saved safely to local storage.',
          backupTime: now,
          sizeBytes: sizeBytes,
          localFilePath: localPath,
          stats: backupData['stats'] as Map<String, dynamic>?,
        );
      }

      final existingFile = await findCloudBackup(ensureScope: true);

      if (existingFile != null) {
        // Update existing file via PATCH
        final patchUri = Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files/${existingFile.fileId}?uploadType=media&supportsAllDrives=true',
        );

        final patchHeaders = Map<String, String>.from(headers)
          ..addAll({'Content-Type': 'application/json; charset=UTF-8'});

        final response =
            await http.patch(patchUri, headers: patchHeaders, body: jsonBytes);

        if (response.statusCode == 200) {
          await _persistBackupMetadata(now, sizeBytes);

          return BackupResult(
            success: true,
            message: 'Successfully updated Google Drive backup.',
            backupTime: now,
            sizeBytes: sizeBytes,
            stats: backupData['stats'] as Map<String, dynamic>?,
            localFilePath: localPath,
          );
        } else if (response.statusCode != 404) {
          final errorExplanation = _parseGoogleApiError(response);
          return BackupResult(
            success: false,
            message: errorExplanation,
            backupTime: now,
            sizeBytes: sizeBytes,
            stats: backupData['stats'] as Map<String, dynamic>?,
            localFilePath: localPath,
          );
        }
        // If 404 (file removed), fall through to multipart create
      }

      // Create new file via Multipart upload
      final boundary =
          '-------fairshare_${DateTime.now().millisecondsSinceEpoch}';
      final uploadUri = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true',
      );

      final uploadHeaders = Map<String, String>.from(headers)
        ..addAll({
          'Content-Type': 'multipart/related; boundary=$boundary',
        });

      final metadata = jsonEncode({
        'name': backupFileName,
        'mimeType': 'application/json',
        'description': 'FairShare Database Backup',
      });

      final body = _buildMultipartBody(boundary, metadata, jsonBytes);
      final response =
          await http.post(uploadUri, headers: uploadHeaders, body: body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _persistBackupMetadata(now, sizeBytes);

        return BackupResult(
          success: true,
          message: 'Successfully backed up to Google Drive.',
          backupTime: now,
          sizeBytes: sizeBytes,
          stats: backupData['stats'] as Map<String, dynamic>?,
          localFilePath: localPath,
        );
      } else {
        final errorExplanation = _parseGoogleApiError(response);
        return BackupResult(
          success: false,
          message: errorExplanation,
          backupTime: now,
          sizeBytes: sizeBytes,
          stats: backupData['stats'] as Map<String, dynamic>?,
          localFilePath: localPath,
        );
      }
    } catch (e) {
      debugPrint('GoogleDriveBackupService: error uploading backup: $e');
      return BackupResult(
        success: false,
        message: 'Cloud backup failed: $e. Backup saved locally.',
        backupTime: now,
        sizeBytes: sizeBytes,
        stats: backupData['stats'] as Map<String, dynamic>?,
        localFilePath: localPath,
      );
    }
  }

  /// Parses error responses from Google APIs and produces human-friendly diagnosis
  String _parseGoogleApiError(http.Response response) {
    debugPrint('GoogleDrive API Error [${response.statusCode}]: ${response.body}');
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['error'] != null) {
        final err = data['error'];
        if (err is Map<String, dynamic>) {
          final message = err['message']?.toString() ?? '';
          final errors = err['errors'] as List?;
          String? reason;
          if (errors != null && errors.isNotEmpty && errors.first is Map) {
            reason = errors.first['reason']?.toString();
          }

          if (reason == 'accessNotConfigured' ||
              message.contains('has not been used in project') ||
              message.contains('disabled')) {
            return 'Google Drive API is disabled in your Google Cloud project. Enable "Google Drive API" in Google Cloud Console. Your data is safely saved locally.';
          }

          if (reason == 'insufficientPermissions' ||
              message.contains('insufficient authentication scopes') ||
              message.contains('ACCESS_TOKEN_SCOPE_INSUFFICIENT')) {
            return 'Google Drive permission not granted. Please sign in again and allow Google Drive access. Your data is safely saved locally.';
          }

          if (message.isNotEmpty) {
            return '$message (Saved locally).';
          }
        }
      }
    } catch (_) {}
    return 'Google Drive returned ${response.statusCode}: ${response.reasonPhrase}. Saved locally.';
  }

  /// Download the backup JSON payload from Google Drive
  Future<Map<String, dynamic>?> downloadCloudBackup() async {
    try {
      await _authService.ensureDriveScope();
      final headers = await _authService.getAuthHeaders();
      if (headers == null) {
        debugPrint('GoogleDriveBackupService: downloadCloudBackup - no auth headers');
        return null;
      }

      final rootUri = Uri.https(
        'www.googleapis.com',
        '/drive/v3/files',
        {
          'q': "name = '$backupFileName' and trashed = false",
          'spaces': 'drive',
          'orderBy': 'modifiedTime desc',
          'pageSize': '10',
          'fields': 'files(id,name,modifiedTime,size)',
          'supportsAllDrives': 'true',
          'includeItemsFromAllDrives': 'true',
        },
      );

      final response = await http.get(rootUri, headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final files = data['files'] as List?;
        if (files != null && files.isNotEmpty) {
          for (final f in files) {
            final fileId = f['id']?.toString();
            if (fileId == null || fileId.isEmpty) continue;

            final downloadUri = Uri.parse(
              'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&supportsAllDrives=true',
            );

            final dlResponse = await http.get(downloadUri, headers: headers);
            if (dlResponse.statusCode == 200) {
              final decoded = jsonDecode(utf8.decode(dlResponse.bodyBytes));
              if (decoded is Map<String, dynamic> && decoded['tables'] != null) {
                debugPrint('GoogleDriveBackupService: successfully downloaded backup from fileId=$fileId');
                return decoded;
              }
            } else {
              debugPrint('GoogleDriveBackupService: failed downloading fileId=$fileId (${dlResponse.statusCode})');
            }
          }
        } else {
          debugPrint('GoogleDriveBackupService: downloadCloudBackup found 0 files matching $backupFileName');
        }
      } else {
        debugPrint(
            'GoogleDriveBackupService: downloadCloudBackup search returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('GoogleDriveBackupService: error downloading backup: $e');
    }
    return null;
  }

  /// Save backup JSON to local storage cache as emergency fallback
  Future<String> saveLocalBackup(Map<String, dynamic> backupData) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$backupFileName');
      await file.writeAsString(jsonEncode(backupData), flush: true);
      return file.path;
    } catch (e) {
      debugPrint('GoogleDriveBackupService: error saving local cache: $e');
      return '';
    }
  }

  /// Retrieve the locally cached backup payload if available
  Future<Map<String, dynamic>?> getLocalBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$backupFileName');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Export backup JSON to a shareable file in temporary directory
  Future<String?> exportToShareableFile(Map<String, dynamic> backupData) async {
    try {
      final dir = await getTemporaryDirectory();
      final dateStr = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}/fairshare_backup_$dateStr.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(backupData),
        flush: true,
      );
      return file.path;
    } catch (e) {
      debugPrint('GoogleDriveBackupService: error exporting share file: $e');
      return null;
    }
  }

  Future<void> _persistBackupMetadata(DateTime time, int sizeBytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastBackupTime, time.toIso8601String());
      await prefs.setInt(_prefLastBackupSize, sizeBytes);
    } catch (_) {}
  }

  List<int> _buildMultipartBody(
    String boundary,
    String jsonMetadata,
    List<int> fileBytes,
  ) {
    final delimiter = '--$boundary\r\n';
    final closeDelimiter = '\r\n--$boundary--\r\n';

    final buffer = BytesBuilder();
    buffer.add(utf8.encode(delimiter));
    buffer.add(utf8.encode(
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$jsonMetadata\r\n',
    ));
    buffer.add(utf8.encode(delimiter));
    buffer.add(utf8.encode(
      'Content-Type: application/json; charset=UTF-8\r\n\r\n',
    ));
    buffer.add(fileBytes);
    buffer.add(utf8.encode(closeDelimiter));
    return buffer.toBytes();
  }
}
