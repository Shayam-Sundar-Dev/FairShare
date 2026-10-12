import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/event_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import 'auth_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/phone_helper.dart';

class TripSyncResult {
  final bool success;
  final String message;
  final String? driveFileId;
  final String? shareCode;
  final Map<String, dynamic>? tripPayload;

  const TripSyncResult({
    required this.success,
    required this.message,
    this.driveFileId,
    this.shareCode,
    this.tripPayload,
  });
}

class GoogleDriveTripSyncService {
  final AuthService _authService;

  GoogleDriveTripSyncService({AuthService? authService})
      : _authService = authService ?? AuthService();

  static String generateShareCode(String fileId) {
    if (fileId.length <= 6) return fileId.toUpperCase();
    final clean = fileId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (clean.length < 6) return fileId.substring(0, 6).toUpperCase();
    return clean.substring(clean.length - 6).toUpperCase();
  }

  /// Extracts the Google Drive File or Folder ID from links, full messages, or raw IDs
  static String? extractDriveFileId(String input) {
    final text = input.trim();

    // 1. Check for Google Drive folder link /folders/{folderId}
    final folderMatch = RegExp(r'/folders/([a-zA-Z0-9_-]{25,})').firstMatch(text);
    if (folderMatch != null) return folderMatch.group(1);

    // 2. Check for standard Google Drive /file/d/{fileId}
    final fileMatch = RegExp(r'/file/d/([a-zA-Z0-9_-]{25,})').firstMatch(text);
    if (fileMatch != null) return fileMatch.group(1);

    // 3. Check for id={fileId} query parameter
    final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]{25,})').firstMatch(text);
    if (idMatch != null) return idMatch.group(1);

    // 4. Check for drive.google.com/uc?id={fileId}
    final ucMatch = RegExp(r'/uc\?.*?id=([a-zA-Z0-9_-]{25,})').firstMatch(text);
    if (ucMatch != null) return ucMatch.group(1);

    // 5. Raw Google Drive file or folder ID (usually 25 to 60 characters)
    if (RegExp(r'^[a-zA-Z0-9_-]{25,60}$').hasMatch(text)) {
      return text;
    }

    return null;
  }

  /// Extracts a clean 6-character code or resolves links from text/clipboard
  static String extractCleanCode(String input) {
    final text = input.trim();

    // 1. If an entire message or link with a Drive file ID was pasted, extract the file ID
    final driveId = extractDriveFileId(text);
    if (driveId != null) return driveId;

    // 2. Check for labeled or formatted 6-char code e.g. "Code: 7X9K2A", "`7X9K2A`", "*7X9K2A*"
    final codeMatch = RegExp(r'(?:Code:?\s*|`|\*)([A-Za-z0-9]{6})(?:`|\*|\s|$)').firstMatch(text);
    if (codeMatch != null) return codeMatch.group(1)!.toUpperCase();

    // 3. If short 6-8 character string, uppercase it
    if (text.length <= 8) {
      return text.toUpperCase();
    }

    return text;
  }

  /// Exports and uploads the trip to Google Drive as a shared folder and master file
  Future<TripSyncResult> shareTripToGoogleDrive({
    required EventModel event,
    required List<ExpenseModel> expenses,
    List<SettlementModel> settlements = const [],
    String? creatorPhone,
  }) async {
    try {
      await _authService.ensureDriveScope();
      final headers = await _authService.getAuthHeaders();
      if (headers == null) {
        return const TripSyncResult(
          success: false,
          message: 'Please sign in to Google to share trips via Google Drive.',
        );
      }

      String existingId = event.driveFileId ?? '';
      String folderId = '';

      // Check if existingId is already a folder
      if (existingId.isNotEmpty) {
        if (await isFolder(existingId, headers)) {
          folderId = existingId;
        }
      }

      // If no folder yet, search if one was already created for this trip
      if (folderId.isEmpty) {
        folderId = await _findTripFolder(event.id, headers) ?? '';
      }

      // If still no folder, create a new shared folder for the trip
      if (folderId.isEmpty) {
        folderId = await createSharedTripFolder(event, headers);
        if (existingId.isNotEmpty && folderId.isNotEmpty && existingId != folderId) {
          // If existingId was a legacy file, add it to the newly created folder
          try {
            await http.patch(
              Uri.parse('https://www.googleapis.com/drive/v3/files/$existingId?addParents=$folderId&supportsAllDrives=true'),
              headers: headers,
            );
          } catch (_) {}
        }
      }

      final authUser = await _authService.getCurrentUser();
      final effectiveCreatorId = (event.creatorId != null && event.creatorId!.isNotEmpty) ? event.creatorId : authUser?.id;
      final effectiveCreatorEmail = (event.creatorEmail != null && event.creatorEmail!.isNotEmpty) ? event.creatorEmail : authUser?.email;
      final effectiveEvent = event.copyWith(creatorId: effectiveCreatorId, creatorEmail: effectiveCreatorEmail);

      final payload = _buildTripPayload(effectiveEvent, expenses, settlements, creatorPhone: creatorPhone);
      payload['folder_id'] = folderId;
      final jsonBytes = utf8.encode(jsonEncode(payload));
      final fileName = 'fairshare_trip_${event.id}.json';

      // Find or create master file inside folder
      String masterFileId = '';
      if (folderId.isNotEmpty) {
        final files = await getFilesInFolder(folderId, headers);
        final masterFiles = files.where((f) {
          final name = (f['name'] as String? ?? '').toLowerCase();
          return name.startsWith('fairshare_trip_') ||
              (name.contains('fairshare_trip') && name.endsWith('.json'));
        }).toList();

        if (masterFiles.isNotEmpty) {
          masterFileId = masterFiles.first['id'] as String;
          // Clean up any duplicate master files created earlier
          for (int i = 1; i < masterFiles.length; i++) {
            final staleId = masterFiles[i]['id'] as String?;
            if (staleId != null && staleId.isNotEmpty) {
              try {
                await http.delete(
                  Uri.parse('https://www.googleapis.com/drive/v3/files/$staleId?supportsAllDrives=true'),
                  headers: headers,
                );
              } catch (_) {}
            }
          }
        }
      }
      if (masterFileId.isEmpty && existingId.isNotEmpty && existingId != folderId) {
        masterFileId = existingId;
      }

      if (masterFileId.isNotEmpty) {
        // Update existing master file
        final patchUri = Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files/$masterFileId?uploadType=media&supportsAllDrives=true',
        );
        final patchHeaders = Map<String, String>.from(headers)
          ..addAll({'Content-Type': 'application/json; charset=UTF-8'});
        final response = await http.patch(patchUri, headers: patchHeaders, body: jsonBytes);
        if (response.statusCode == 200) {
          await _makeFileShareable(masterFileId, headers);
          final shareId = folderId.isNotEmpty ? folderId : masterFileId;
          final shareCode = event.shareCode ?? generateShareCode(shareId);
          _patchFileMetadata(masterFileId, shareCode, event, headers);
          return TripSyncResult(
            success: true,
            message: 'Trip updated on Google Drive.',
            driveFileId: shareId,
            shareCode: shareCode,
            tripPayload: payload,
          );
        }
      }

      // Create new master file inside folder
      masterFileId = await _createFileInFolder(
        folderId: folderId,
        name: fileName,
        contentBytes: jsonBytes,
        headers: headers,
        event: event,
      );

      if (masterFileId.isNotEmpty) {
        await _makeFileShareable(masterFileId, headers);
        final shareId = folderId.isNotEmpty ? folderId : masterFileId;
        final shareCode = generateShareCode(shareId);
        _patchFileMetadata(masterFileId, shareCode, event, headers);
        return TripSyncResult(
          success: true,
          message: 'Trip shared successfully via Google Drive!',
          driveFileId: shareId,
          shareCode: shareCode,
          tripPayload: payload,
        );
      } else {
        return const TripSyncResult(
          success: false,
          message: 'Failed to create trip file on Google Drive.',
        );
      }
    } catch (e) {
      debugPrint('GoogleDriveTripSyncService share error: $e');
      return TripSyncResult(
        success: false,
        message: 'Failed to share trip: $e',
      );
    }
  }

  Future<bool> isFolder(String id, Map<String, String> headers) async {
    try {
      final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$id?fields=mimeType&supportsAllDrives=true');
      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['mimeType'] == 'application/vnd.google-apps.folder';
      }
    } catch (_) {}
    return false;
  }

  Future<String> createSharedTripFolder(EventModel event, Map<String, String> headers) async {
    try {
      final uri = Uri.parse('https://www.googleapis.com/drive/v3/files?supportsAllDrives=true');
      final reqHeaders = Map<String, String>.from(headers)
        ..addAll({'Content-Type': 'application/json; charset=UTF-8'});
      final body = jsonEncode({
        'name': 'fairshare_trip_${event.id}_folder',
        'mimeType': 'application/vnd.google-apps.folder',
        'description': 'FairShare Shared Trip: ${event.title}',
        'appProperties': {
          'app': 'FairShare',
          'trip_id': event.id,
          'trip_title': event.title,
        },
      });
      final res = await http.post(uri, headers: reqHeaders, body: body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final folderId = jsonDecode(res.body)['id'] as String;
        await _makeFileShareable(folderId, headers);
        return folderId;
      }
    } catch (e) {
      debugPrint('createSharedTripFolder error: $e');
    }
    return '';
  }

  Future<String?> _findTripFolder(String eventId, Map<String, String> headers) async {
    try {
      final searchUri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?q=mimeType+%3D+%27application/vnd.google-apps.folder%27+and+name+contains+%27$eventId%27+and+trashed+%3D+false'
        '&supportsAllDrives=true'
        '&includeItemsFromAllDrives=true'
        '&fields=files(id,name)',
      );
      final res = await http.get(searchUri, headers: headers);
      if (res.statusCode == 200) {
        final files = (jsonDecode(res.body)['files'] as List?) ?? [];
        if (files.isNotEmpty) {
          return files.first['id'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Lists all active files in a shared Google Drive folder ordered by most recently modified
  Future<List<Map<String, dynamic>>> getFilesInFolder(String folderId, Map<String, String> headers) async {
    if (folderId.isEmpty) return [];
    try {
      final searchUri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?q=%27$folderId%27+in+parents+and+trashed+%3D+false'
        '&supportsAllDrives=true'
        '&includeItemsFromAllDrives=true'
        '&orderBy=modifiedTime+desc'
        '&fields=files(id,name,mimeType,modifiedTime)',
      );
      final res = await http.get(searchUri, headers: headers);
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body)['files'] as List?) ?? [];
        return List<Map<String, dynamic>>.from(list);
      }
    } catch (e) {
      debugPrint('Error getting files in folder $folderId: $e');
    }
    return [];
  }

  Future<String?> findMasterFileInFolder(String folderId, String eventId, Map<String, String> headers) async {
    if (folderId.isEmpty) return null;
    try {
      final files = await getFilesInFolder(folderId, headers);
      for (final f in files) {
        final name = (f['name'] as String? ?? '').toLowerCase();
        if (name.startsWith('fairshare_trip_') ||
            (name.contains('fairshare_trip') && name.endsWith('.json'))) {
          return f['id'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String> _createFileInFolder({
    required String folderId,
    required String name,
    required List<int> contentBytes,
    required Map<String, String> headers,
    required EventModel event,
  }) async {
    try {
      final boundary = '-------fairshare_${DateTime.now().millisecondsSinceEpoch}';
      final uploadUri = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true',
      );
      final uploadHeaders = Map<String, String>.from(headers)
        ..addAll({'Content-Type': 'multipart/related; boundary=$boundary'});

      final metadata = <String, dynamic>{
        'name': name,
        'mimeType': 'application/json',
        'description': 'FairShare Shared Trip: ${event.title}',
        'appProperties': {
          'app': 'FairShare',
          'trip_id': event.id,
          'trip_title': event.title,
        },
      };
      if (folderId.isNotEmpty) {
        metadata['parents'] = [folderId];
      }

      final body = _buildMultipartBody(boundary, jsonEncode(metadata), contentBytes);
      final response = await http.post(uploadUri, headers: uploadHeaders, body: body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body)['id'] as String;
      }
    } catch (e) {
      debugPrint('Error creating file in folder: $e');
    }
    return '';
  }

  void _patchFileMetadata(
    String fileId,
    String shareCode,
    EventModel event,
    Map<String, String> headers,
  ) {
    try {
      final patchMetaUri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId');
      final patchMetaHeaders = Map<String, String>.from(headers)
        ..addAll({'Content-Type': 'application/json; charset=UTF-8'});
      http.patch(
        patchMetaUri,
        headers: patchMetaHeaders,
        body: jsonEncode({
          'name': 'fairshare_trip_${shareCode}_${event.id}.json',
          'description': 'FairShare Shared Trip: ${event.title} (Code: $shareCode)',
          'appProperties': {
            'app': 'FairShare',
            'trip_id': event.id,
            'trip_title': event.title,
            'share_code': shareCode,
          },
          'properties': {
            'share_code': shareCode,
          },
        }),
      );
    } catch (_) {}
  }

  /// Sets permission on the drive file so anyone with the link / code can view and edit
  Future<void> _makeFileShareable(String fileId, Map<String, String> headers) async {
    try {
      final permUri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId/permissions',
      );
      final permHeaders = Map<String, String>.from(headers)
        ..addAll({'Content-Type': 'application/json; charset=UTF-8'});

      final permBody = jsonEncode({
        'role': 'writer',
        'type': 'anyone',
      });

      await http.post(permUri, headers: permHeaders, body: permBody);
    } catch (e) {
      debugPrint('Error granting permissions to shared trip file: $e');
    }
  }

  /// Downloads trip data from Google Drive given a folderId, fileId, shareCode, or Drive link
  Future<Map<String, dynamic>?> downloadTripData(String fileIdOrCode) async {
    try {
      final rawInput = fileIdOrCode.trim();
      if (rawInput.isEmpty) return null;

      final extractedId = extractDriveFileId(rawInput);
      String targetId = extractedId ?? extractCleanCode(rawInput);

      Map<String, String>? headers;
      try {
        headers = await _authService.getAuthHeaders();
      } catch (_) {}

      // If user passed a 6-character code, search by code
      if (targetId.length <= 8 && !targetId.contains('-') && !targetId.contains('_')) {
        if (headers != null && headers.isNotEmpty) {
          final found = await _findFileByShareCode(targetId, headers);
          if (found != null) {
            targetId = found;
          }
        }
      }

      if (targetId.length <= 8 && !targetId.contains('-') && !targetId.contains('_')) {
        debugPrint('Could not resolve share code "$targetId" to a Google Drive ID');
        return null;
      }

      // Check if targetId is a folder
      if (headers != null && headers.isNotEmpty) {
        try {
          final isFld = await isFolder(targetId, headers);
          if (isFld) {
            final files = await getFilesInFolder(targetId, headers);
            Map<String, dynamic>? masterFile;
            for (final f in files) {
              final name = (f['name'] as String? ?? '').toLowerCase();
              if (name.startsWith('fairshare_trip_') ||
                  (name.contains('fairshare_trip') && name.endsWith('.json'))) {
                masterFile = f;
                break;
              }
            }
            if (masterFile != null) {
              final masterId = masterFile['id'] as String;
              final dlUri = Uri.parse('https://www.googleapis.com/drive/v3/files/$masterId?alt=media&supportsAllDrives=true');
              final dlRes = await http.get(dlUri, headers: headers);
              if (dlRes.statusCode == 200) {
                final decoded = jsonDecode(utf8.decode(dlRes.bodyBytes));
                if (decoded is Map<String, dynamic> && decoded['trip_id'] != null) {
                  decoded['resolved_file_id'] = masterId;
                  decoded['folder_id'] = targetId;
                  decoded['resolved_folder_id'] = targetId;
                  return decoded;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error inspecting folder in downloadTripData: $e');
        }
      }

      // Method 1: Authenticated Google Drive API v3 (for single file)
      if (headers != null && headers.isNotEmpty) {
        try {
          final downloadUri = Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$targetId?alt=media&supportsAllDrives=true',
          );
          final response = await http.get(downloadUri, headers: headers);
          if (response.statusCode == 200) {
            final decoded = jsonDecode(utf8.decode(response.bodyBytes));
            if (decoded is Map<String, dynamic> && decoded['trip_id'] != null) {
              decoded['resolved_file_id'] = targetId;
              return decoded;
            }
          }
        } catch (e) {
          debugPrint('Drive API v3 download attempt error: $e');
        }
      }

      // Method 2: Public direct download
      try {
        final publicUri = Uri.parse(
          'https://drive.google.com/uc?export=download&id=$targetId',
        );
        final response = await http.get(publicUri);
        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic> && decoded['trip_id'] != null) {
            decoded['resolved_file_id'] = targetId;
            return decoded;
          }
        }
      } catch (e) {
        debugPrint('Public Drive direct download attempt error: $e');
      }

      // Method 3: Alternative export endpoint
      try {
        final altUri = Uri.parse(
          'https://docs.google.com/uc?export=download&id=$targetId',
        );
        final response = await http.get(altUri);
        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic> && decoded['trip_id'] != null) {
            decoded['resolved_file_id'] = targetId;
            return decoded;
          }
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('GoogleDriveTripSyncService download error: $e');
    }
    return null;
  }

  /// Pushes participant's local expenses and member info as a patch file inside the shared folder
  Future<bool> pushParticipantPatch({
    required String folderId,
    required String eventId,
    required String participantId,
    required List<ExpenseModel> expenses,
    String? phoneNumber,
    String? upiId,
  }) async {
    if (folderId.isEmpty) return false;
    try {
      await _authService.ensureDriveScope();
      final headers = await _authService.getAuthHeaders();
      if (headers == null) return false;

      final patchFileName = 'fairshare_patch_${eventId}_$participantId.json';
      final patchPayload = {
        'schema_version': 2,
        'patch_version': 1,
        'trip_id': eventId,
        'participant_id': participantId,
        'phone_number': phoneNumber,
        'upi_id': upiId,
        'updated_at': DateTime.now().toIso8601String(),
        'expenses': expenses.map((e) => e.toMap(includeSplits: true)).toList(),
      };
      final jsonBytes = utf8.encode(jsonEncode(patchPayload));

      // Search if this participant already created their patch file in the folder
      final files = await getFilesInFolder(folderId, headers);
      String? existingPatchId;
      for (final f in files) {
        final name = f['name'] as String? ?? '';
        if (name == patchFileName || name.startsWith('fairshare_patch_${eventId}_$participantId')) {
          existingPatchId = f['id'] as String?;
          break;
        }
      }

      if (existingPatchId != null && existingPatchId.isNotEmpty) {
        // Update existing patch file
        final patchUri = Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files/$existingPatchId?uploadType=media&supportsAllDrives=true',
        );
        final patchHeaders = Map<String, String>.from(headers)
          ..addAll({'Content-Type': 'application/json; charset=UTF-8'});
        final res = await http.patch(patchUri, headers: patchHeaders, body: jsonBytes);
        if (res.statusCode == 200) {
          await _makeFileShareable(existingPatchId, headers);
          DebugLog.lastLog = 'PATCH UPDATED: $existingPatchId';
          return true;
        }
      }

      // Create new patch file inside folder
      final createUri = Uri.parse('https://www.googleapis.com/drive/v3/files?supportsAllDrives=true');
      final createHeaders = Map<String, String>.from(headers)
        ..addAll({'Content-Type': 'application/json; charset=UTF-8'});
      final createRes = await http.post(
        createUri,
        headers: createHeaders,
        body: jsonEncode({
          'name': patchFileName,
          'mimeType': 'application/json',
          'parents': [folderId],
        }),
      );
      if (createRes.statusCode == 200 || createRes.statusCode == 201) {
        final newId = jsonDecode(createRes.body)['id'] as String;
        final uploadUri = Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files/$newId?uploadType=media&supportsAllDrives=true',
        );
        await http.patch(uploadUri, headers: createHeaders, body: jsonBytes);
        await _makeFileShareable(newId, headers);
        DebugLog.lastLog = 'PATCH CREATED: $newId';
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error pushing participant patch: $e');
      return false;
    }
  }

  /// Fetches all participant patch files inside the shared folder, deduplicating
  /// multiple patches from the same participant so only the latest patch is retained.
  Future<List<Map<String, dynamic>>> fetchParticipantPatches(String folderId) async {
    final rawPatches = <Map<String, dynamic>>[];
    if (folderId.isEmpty) return rawPatches;
    try {
      final headers = await _authService.getAuthHeaders();
      if (headers == null) return rawPatches;

      final files = await getFilesInFolder(folderId, headers);
      for (final f in files) {
        final name = (f['name'] as String? ?? '').toLowerCase();
        if (name.startsWith('fairshare_patch_') ||
            (name.contains('fairshare_patch') && name.endsWith('.json'))) {
          final fileId = f['id'] as String? ?? '';
          if (fileId.isEmpty) continue;
          try {
            Map<String, dynamic>? data;
            final dlUri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media&supportsAllDrives=true');
            final dlRes = await http.get(dlUri, headers: headers);
            if (dlRes.statusCode == 200) {
              final decoded = jsonDecode(utf8.decode(dlRes.bodyBytes));
              if (decoded is Map<String, dynamic>) {
                data = decoded;
              }
            } else {
              final pubUri = Uri.parse('https://drive.google.com/uc?export=download&id=$fileId');
              final pubRes = await http.get(pubUri);
              if (pubRes.statusCode == 200) {
                final decoded = jsonDecode(utf8.decode(pubRes.bodyBytes));
                if (decoded is Map<String, dynamic>) {
                  data = decoded;
                }
              }
            }
            if (data != null) {
              data['_drive_file_id'] = fileId;
              data['_modified_time'] = f['modifiedTime'];
              rawPatches.add(data);
            }
          } catch (_) {}
        }
      }

      // Deduplicate patches by participant: if multiple patches exist for the same participant phone/ID, keep ONLY the latest one
      final Map<String, Map<String, dynamic>> latestPatchesByParticipant = {};
      final List<String> staleFileIds = [];

      for (final patch in rawPatches) {
        final phone = (patch['phone_number'] as String?)?.trim() ?? '';
        final pid = (patch['participant_id'] as String?)?.trim() ?? '';
        final updatedStr = (patch['updated_at'] as String?) ?? (patch['_modified_time'] as String?) ?? '';
        final DateTime patchTime = DateTime.tryParse(updatedStr) ?? DateTime(2000);

        // Find key for grouping: normalized phone (last 10 digits) or pid
        String groupKey = phone.isNotEmpty ? PhoneHelper.last10(phone) : pid;
        if (groupKey.isEmpty) groupKey = patch['_drive_file_id'] ?? '';

        if (!latestPatchesByParticipant.containsKey(groupKey)) {
          latestPatchesByParticipant[groupKey] = patch;
        } else {
          final existingPatch = latestPatchesByParticipant[groupKey]!;
          final existingUpdatedStr = (existingPatch['updated_at'] as String?) ?? (existingPatch['_modified_time'] as String?) ?? '';
          final DateTime existingTime = DateTime.tryParse(existingUpdatedStr) ?? DateTime(2000);

          if (patchTime.isAfter(existingTime)) {
            // New patch is newer; mark existing as stale
            final oldId = existingPatch['_drive_file_id'] as String?;
            if (oldId != null && oldId.isNotEmpty) staleFileIds.add(oldId);
            latestPatchesByParticipant[groupKey] = patch;
          } else {
            // Current patch is older; mark current as stale
            final oldId = patch['_drive_file_id'] as String?;
            if (oldId != null && oldId.isNotEmpty) staleFileIds.add(oldId);
          }
        }
      }

      // Clean up stale patch files from Google Drive
      for (final oldFileId in staleFileIds) {
        try {
          final delUri = Uri.parse('https://www.googleapis.com/drive/v3/files/$oldFileId?supportsAllDrives=true');
          await http.delete(delUri, headers: headers);
          debugPrint('Deleted stale participant patch from Drive: $oldFileId');
        } catch (e) {
          debugPrint('Failed to delete stale patch: $e');
        }
      }

      return latestPatchesByParticipant.values.toList();
    } catch (e) {
      debugPrint('Error fetching participant patches: $e');
    }
    return [];
  }


  /// Submits a participant expense to the shared Google Drive trip file under pending_expenses
  Future<bool> submitPendingExpenseToDrive({
    required String driveFileId,
    required ExpenseModel expense,
  }) async {
    try {
      final tripData = await downloadTripData(driveFileId);
      if (tripData == null) return false;

      final pendingList = List<Map<String, dynamic>>.from(tripData['pending_expenses'] ?? []);
      // Remove any existing copy of this expense
      pendingList.removeWhere((item) => item['id'] == expense.id);
      pendingList.add(expense.toMap(includeSplits: true));
      tripData['pending_expenses'] = pendingList;
      tripData['last_synced_at'] = DateTime.now().toIso8601String();

      return await _updateDriveFile(driveFileId, tripData);
    } catch (e) {
      debugPrint('Error submitting pending expense to drive: $e');
      return false;
    }
  }

  /// Updates approval status in the Drive file (approves or rejects an expense)
  Future<bool> updateExpenseApprovalInDrive({
    required String driveFileId,
    required String expenseId,
    required bool isApproved,
    String? rejectionReason,
  }) async {
    try {
      final tripData = await downloadTripData(driveFileId);
      if (tripData == null) return false;

      final pendingList = List<Map<String, dynamic>>.from(tripData['pending_expenses'] ?? []);
      final approvedList = List<Map<String, dynamic>>.from(tripData['approved_expenses'] ?? []);

      final targetMapIndex = pendingList.indexWhere((item) => item['id'] == expenseId);
      if (targetMapIndex != -1) {
        final expenseMap = Map<String, dynamic>.from(pendingList.removeAt(targetMapIndex));
        if (isApproved) {
          expenseMap['approval_status'] = ExpenseApprovalStatus.approved.dbValue;
          expenseMap['approved_at'] = DateTime.now().millisecondsSinceEpoch;
          expenseMap['rejection_reason'] = null;
          approvedList.add(expenseMap);
        } else {
          expenseMap['approval_status'] = ExpenseApprovalStatus.rejected.dbValue;
          expenseMap['rejection_reason'] = rejectionReason;
          pendingList.add(expenseMap);
        }

        tripData['pending_expenses'] = pendingList;
        tripData['approved_expenses'] = approvedList;
        tripData['last_synced_at'] = DateTime.now().toIso8601String();

        return await _updateDriveFile(driveFileId, tripData);
      }
      return false;
    } catch (e) {
      debugPrint('Error updating expense approval in drive: $e');
      return false;
    }
  }

  Future<bool> updateDriveFile(String fileId, Map<String, dynamic> data) async {
    return await _updateDriveFile(fileId, data);
  }

  Future<bool> _updateDriveFile(String fileId, Map<String, dynamic> data) async {
    try {
      await _authService.ensureDriveScope();
      final headers = await _authService.getAuthHeaders();
      if (headers == null) {
        DebugLog.lastLog = 'ERROR: headers is null';
        return false;
      }

      final patchUri = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media&supportsAllDrives=true',
      );
      final patchHeaders = Map<String, String>.from(headers)
        ..addAll({'Content-Type': 'application/json; charset=UTF-8'});

      final jsonBytes = utf8.encode(jsonEncode(data));
      final response = await http.patch(patchUri, headers: patchHeaders, body: jsonBytes);
      if (response.statusCode != 200) {
        DebugLog.lastLog = 'STATUS: ${response.statusCode}, BODY: ${response.body}';
        // If updating file failed (e.g. 404 because participant has drive.file scope and file is owned by host),
        // fallback to pushParticipantPatch if folder_id is available!
        final folderId = data['folder_id']?.toString() ?? '';
        final tripId = data['trip_id']?.toString() ?? '';
        final pending = List<Map<String, dynamic>>.from(data['pending_expenses'] ?? []);
        if (folderId.isNotEmpty && tripId.isNotEmpty && pending.isNotEmpty) {
          final exps = pending.map((m) => ExpenseModel.fromMap(m)).toList();
          final user = await _authService.getCurrentUser();
          return await pushParticipantPatch(
            folderId: folderId,
            eventId: tripId,
            participantId: user?.id ?? 'p_${DateTime.now().millisecondsSinceEpoch}',
            expenses: exps,
          );
        }
      } else {
        DebugLog.lastLog = 'SUCCESS 200';
      }
      return response.statusCode == 200;
    } catch (e, st) {
      DebugLog.lastLog = 'EXCEPTION: $e\n$st';
      return false;
    }
  }

  Future<String?> _findFileByShareCode(String code, Map<String, String> headers) async {
    final cleanCode = code.trim().toUpperCase();
    try {
      // Use query without trailing underscores which breaks word-token matching in Google Drive v3
      final searchUri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?q=trashed%3Dfalse%20and%20name%20contains%20%27fairshare%27'
        '&spaces=drive'
        '&supportsAllDrives=true'
        '&includeItemsFromAllDrives=true'
        '&fields=files(id,name,description,appProperties,properties)',
      );

      final response = await http.get(searchUri, headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final files = data['files'] as List?;
        if (files != null) {
          for (final f in files) {
            final id = f['id'] as String? ?? '';
            final name = (f['name'] as String? ?? '').toUpperCase();
            final desc = (f['description'] as String? ?? '').toUpperCase();
            final appProps = f['appProperties'] as Map<String, dynamic>?;
            final props = f['properties'] as Map<String, dynamic>?;

            if (generateShareCode(id) == cleanCode) {
              return id;
            }
            if (name.contains(cleanCode)) {
              return id;
            }
            if (appProps?['share_code']?.toString().toUpperCase() == cleanCode ||
                props?['share_code']?.toString().toUpperCase() == cleanCode) {
              return id;
            }
            if (desc.contains(cleanCode)) {
              return id;
            }
          }
        }
      } else {
        debugPrint('Google Drive search failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error searching Google Drive by share code: $e');
    }
    return null;
  }

  Map<String, dynamic> _buildTripPayload(
    EventModel event,
    List<ExpenseModel> expenses,
    List<SettlementModel> settlements, {
    String? creatorPhone,
  }) {
    final membersPayload = event.members.map((m) {
      final map = m.toMap();
      final currentPhone = (map['phone_number'] as String?)?.trim() ?? '';
      if (currentPhone.isEmpty && m.isSelf && creatorPhone != null && creatorPhone.trim().isNotEmpty) {
        map['phone_number'] = creatorPhone.trim();
      }
      return map;
    }).toList();

    return {
      'schema_version': 1,
      'trip_id': event.id,
      'title': event.title,
      'event_type': event.eventType,
      'currency': event.currency,
      'description': event.description,
      'creator_id': event.creatorId,
      'creator_email': event.creatorEmail,
      'creator_phone': creatorPhone,
      'created_at': event.createdAt.millisecondsSinceEpoch,
      'members': membersPayload,
      'approved_expenses': expenses.where((e) => e.isApproved).map((e) => e.toMap(includeSplits: true)).toList(),
      'pending_expenses': expenses.where((e) => e.isPending).map((e) => e.toMap(includeSplits: true)).toList(),
      'settlements': settlements.map((s) => s.toMap()).toList(),
      'last_synced_at': DateTime.now().toIso8601String(),
    };
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
      'Content-Type: application/json; charset=UTF-8\r\n\r\n$jsonMetadata\r\n',
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
