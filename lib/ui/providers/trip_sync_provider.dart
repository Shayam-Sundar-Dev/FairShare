import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/utils/phone_helper.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/event_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/person_model.dart';
import '../../data/models/settlement_model.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/contacts_service.dart';
import '../../data/services/google_drive_trip_sync_service.dart';
import 'event_provider.dart';
import 'expense_provider.dart';

class TripSyncProvider extends ChangeNotifier {
  final GoogleDriveTripSyncService _syncService;
  final EventRepository _eventRepository;
  final ExpenseRepository _expenseRepository;
  final PeopleRepository _peopleRepository;
  final DatabaseHelper _databaseHelper;
  final AuthService _authService;
  final ContactsService _contactsService;

  bool _isSyncing = false;
  String? _errorMessage;
  DateTime? _lastSyncTime;
  List<ExpenseModel> _pendingApprovals = [];

  TripSyncProvider({
    GoogleDriveTripSyncService? syncService,
    EventRepository? eventRepository,
    ExpenseRepository? expenseRepository,
    PeopleRepository? peopleRepository,
    DatabaseHelper? databaseHelper,
    AuthService? authService,
    ContactsService? contactsService,
  })  : _syncService = syncService ?? GoogleDriveTripSyncService(),
        _eventRepository = eventRepository ?? EventRepository(),
        _expenseRepository = expenseRepository ?? ExpenseRepository(),
        _peopleRepository = peopleRepository ?? PeopleRepository(),
        _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _authService = authService ?? AuthService(),
        _contactsService = contactsService ?? ContactsService();

  bool get isSyncing => _isSyncing;
  String? get errorMessage => _errorMessage;
  DateTime? get lastSyncTime => _lastSyncTime;
  List<ExpenseModel> get pendingApprovals => _pendingApprovals;

  Future<void> loadPendingApprovals(String eventId) async {
    try {
      _pendingApprovals = await _expenseRepository.getPendingExpensesForEvent(eventId);
      notifyListeners();
    } catch (_) {}
  }

  /// Shares an event to Google Drive and persists fileId and shareCode locally
  Future<TripSyncResult> shareTripToDrive({
    required EventModel event,
    List<ExpenseModel>? expenses,
    List<SettlementModel> settlements = const [],
    EventProvider? eventProvider,
  }) async {
    _isSyncing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Refresh event with latest members & UPI IDs from database
      final freshEvent = await _eventRepository.getEventById(event.id) ?? event;
      final freshExpenses = await _expenseRepository.getExpensesForEvent(freshEvent.id);
      final freshSettlements = settlements.isNotEmpty
          ? settlements
          : await SettlementRepository().getSettlementsForEvent(freshEvent.id);

      final selfPerson = await _peopleRepository.getSelfPerson();
      String? creatorPhone = selfPerson?.phoneNumber;
      if (creatorPhone == null || creatorPhone.isEmpty) {
        final authUser = await _authService.getCurrentUser();
        if (authUser?.phoneNumber != null && authUser!.phoneNumber!.isNotEmpty) {
          creatorPhone = authUser.phoneNumber;
          if (selfPerson != null) {
            await _peopleRepository.updatePerson(selfPerson.copyWith(phoneNumber: creatorPhone));
          }
        }
      }

      final result = await _syncService.shareTripToGoogleDrive(
        event: freshEvent,
        expenses: freshExpenses,
        settlements: freshSettlements,
        creatorPhone: creatorPhone,
      );

      if (result.success && result.driveFileId != null) {
        await _eventRepository.updateEventDriveSyncInfo(
          eventId: freshEvent.id,
          driveFileId: result.driveFileId!,
          shareCode: result.shareCode ?? GoogleDriveTripSyncService.generateShareCode(result.driveFileId!),
          isShared: true,
          lastSyncedAt: DateTime.now(),
        );
        // Refresh the in-memory event so the card shows the new sync time
        await eventProvider?.refreshEventInList(freshEvent.id);
      } else {
        _errorMessage = result.message;
      }
      return result;
    } catch (e) {
      _errorMessage = e.toString();
      return TripSyncResult(success: false, message: e.toString());
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Joins an existing trip from Google Drive using shareCode or fileId
  Future<EventModel?> joinTripFromDrive(String fileIdOrCode) async {
    _isSyncing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final cleanInput = GoogleDriveTripSyncService.extractCleanCode(fileIdOrCode);

      // Check if this event already exists in local DB
      final localEvent = await _eventRepository.getEventByShareCode(cleanInput) ??
          await _eventRepository.getEventByDriveFileId(cleanInput);

      String lookupId = cleanInput;
      if (localEvent?.driveFileId != null && localEvent!.driveFileId!.isNotEmpty) {
        lookupId = localEvent.driveFileId!;
      }

      final data = await _syncService.downloadTripData(lookupId);
      if (data == null) {
        if (localEvent != null) {
          _isSyncing = false;
          notifyListeners();
          return localEvent;
        }

        final authHeaders = await _authService.getAuthHeaders();
        if (cleanInput.length <= 8 && (authHeaders == null || authHeaders.isEmpty)) {
          _errorMessage =
              'Please sign in to Google in Profile or paste the direct Trip Link / File ID.';
        } else {
          _errorMessage =
              'Could not find trip with this link. Please verify with the organizer or paste the direct link.';
        }
        _isSyncing = false;
        notifyListeners();
        return null;
      }

      final tripId = data['trip_id'] as String;
      final title = data['title'] as String;
      final eventType = data['event_type'] as String? ?? 'Trip';
      final currency = data['currency'] as String? ?? '₹';
      final description = data['description'] as String? ?? '';
      final createdAtMs = data['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      final creatorId = data['creator_id'] as String?;
      final creatorEmail = data['creator_email'] as String?;
      final resolvedFileId = data['resolved_file_id'] as String? ?? fileIdOrCode;
      final shareCode = GoogleDriveTripSyncService.generateShareCode(resolvedFileId);

      final db = await _databaseHelper.database;
      final selfPerson = await _peopleRepository.getSelfPerson();
      final selfUpi = selfPerson?.upiId;
      final authUser = await _authService.getCurrentUser();
      final selfPhone = (selfPerson?.phoneNumber != null && selfPerson!.phoneNumber.isNotEmpty)
          ? selfPerson.phoneNumber
          : (authUser?.phoneNumber ?? '');

      // 1. Insert or update members & synchronize UPI IDs
      final membersList = List<Map<String, dynamic>>.from(data['members'] ?? []);
      final memberPersonIds = <String>[];
      final memberCounts = <String, int>{};
      bool needsDriveUpdate = false;

      for (int i = 0; i < membersList.length; i++) {
        final m = Map<String, dynamic>.from(membersList[i]);
        final person = PersonModel.fromMap(m);

        // Check if this member matches the joining user by contact number or name
        final bool isMatchSelf = (selfPhone.isNotEmpty &&
                person.phoneNumber.isNotEmpty &&
                PhoneHelper.isSamePhone(selfPhone, person.phoneNumber)) ||
            (selfPerson != null &&
                selfPerson.name.toLowerCase() == person.name.toLowerCase() &&
                !person.isSelf);

        String? effectiveUpi = person.upiId;
        if (isMatchSelf && (effectiveUpi == null || effectiveUpi.isEmpty) && (selfUpi != null && selfUpi.isNotEmpty)) {
          effectiveUpi = selfUpi;
          m['upi_id'] = selfUpi;
          membersList[i] = m;
          needsDriveUpdate = true;
        }

        // If matched self and remote didn't have phone number, populate self phone
        if (isMatchSelf && person.phoneNumber.isEmpty && selfPhone.isNotEmpty) {
          m['phone_number'] = selfPhone;
          membersList[i] = m;
          needsDriveUpdate = true;
        }

        // Resolve member name according to device contacts
        String resolvedName = person.name;
        String? matchedContactId = person.contactId;

        if (isMatchSelf) {
          resolvedName = selfPerson?.name ?? person.name;
        } else if (person.phoneNumber.isNotEmpty) {
          final contactName = await _contactsService.findContactNameByPhone(person.phoneNumber);
          if (contactName != null && contactName.isNotEmpty) {
            resolvedName = contactName;
          }
          final contact = await _contactsService.findContactByPhone(person.phoneNumber);
          if (contact != null) {
            matchedContactId = contact.id;
          }
        }

        // Always preserve the member's canonical ID from Drive in the local DB
        final personToSave = PersonModel(
          id: person.id,
          name: resolvedName,
          phoneNumber: person.phoneNumber.isNotEmpty ? person.phoneNumber : (isMatchSelf ? selfPhone : ''),
          contactId: matchedContactId,
          avatarColor: person.avatarColor,
          isSelf: false, // isSelf is dynamically evaluated per-event
          upiId: effectiveUpi ?? person.upiId,
          count: person.count,
        );
        final existingPerson = await _peopleRepository.getPersonById(person.id);
        if (existingPerson == null) {
          await db.insert('people', personToSave.toMap());
        } else {
          await db.update('people', personToSave.toMap(), where: 'id = ?', whereArgs: [person.id]);
        }
        memberPersonIds.add(person.id);
        memberCounts[person.id] = person.count;
      }

      if (needsDriveUpdate) {
        data['members'] = membersList;
        data['last_synced_at'] = DateTime.now().toIso8601String();
        await _syncService.updateDriveFile(resolvedFileId, data);
      }

      // 2. Insert or update Event
      final event = EventModel(
        id: tripId,
        title: title,
        eventType: eventType,
        currency: currency,
        description: description,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
        creatorId: creatorId,
        creatorEmail: creatorEmail,
        driveFileId: resolvedFileId,
        shareCode: shareCode,
        isShared: true,
        lastSyncedAt: DateTime.now(),
      );

      final existingEvent = await _eventRepository.getEventById(tripId);
      if (existingEvent == null) {
        await db.insert('events', event.toMap());
      } else {
        await db.update('events', event.toMap(), where: 'id = ?', whereArgs: [tripId]);
      }

      // 3. Re-assign event participants
      await db.delete('event_participants', where: 'event_id = ?', whereArgs: [tripId]);
      for (final pid in memberPersonIds) {
        await db.insert('event_participants', {
          'event_id': tripId,
          'person_id': pid,
          'count': memberCounts[pid] ?? 1,
        });
      }

      // 4. Import approved and pending expenses
      final approvedList = List<Map<String, dynamic>>.from(data['approved_expenses'] ?? []);
      final pendingList = List<Map<String, dynamic>>.from(data['pending_expenses'] ?? []);

      for (final expMap in [...approvedList, ...pendingList]) {
        try {
          await _importExpenseRecord(db, tripId, expMap);
        } catch (e) {
          debugPrint('Error importing expense on join: $e');
        }
      }

      await loadPendingApprovals(tripId);
      return await _eventRepository.getEventById(tripId);
    } catch (e) {
      _errorMessage = 'Failed to join trip: $e';
      return null;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Submits an expense as a participant to local db and Google Drive pending list
  Future<bool> submitParticipantExpense({
    required EventModel event,
    required ExpenseModel expense,
    EventProvider? eventProvider,
    ExpenseProvider? expenseProvider,
  }) async {
    _isSyncing = true;
    notifyListeners();

    try {
      if (event.driveFileId != null && event.driveFileId!.isNotEmpty) {
        await syncTrip(event, eventProvider: eventProvider, expenseProvider: expenseProvider);
      }
      return true;
    } catch (e) {
      debugPrint('submitParticipantExpense error: $e');
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Approves a pending expense locally and in Google Drive
  Future<bool> approveExpense({
    required EventModel event,
    required ExpenseModel expense,
    EventProvider? eventProvider,
    ExpenseProvider? expenseProvider,
  }) async {
    _isSyncing = true;
    notifyListeners();

    try {
      // 1. Approve in local SQLite
      await _expenseRepository.approveExpense(expense.id);

      // 2. Sync to Drive
      if (event.driveFileId != null && event.driveFileId!.isNotEmpty) {
        await syncTrip(event, eventProvider: eventProvider, expenseProvider: expenseProvider);
      }

      await loadPendingApprovals(event.id);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Rejects a pending expense locally and in Google Drive
  Future<bool> rejectExpense({
    required EventModel event,
    required ExpenseModel expense,
    String? reason,
    EventProvider? eventProvider,
    ExpenseProvider? expenseProvider,
  }) async {
    _isSyncing = true;
    notifyListeners();

    try {
      // 1. Reject in local SQLite
      await _expenseRepository.rejectExpense(expense.id, reason: reason);

      // 2. Sync to Drive
      if (event.driveFileId != null && event.driveFileId!.isNotEmpty) {
        await syncTrip(event, eventProvider: eventProvider, expenseProvider: expenseProvider);
      }

      await loadPendingApprovals(event.id);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Pulls the latest updates from Google Drive and synchronizes members, pending & approved expenses bidirectionally
  Future<void> syncTrip(
    EventModel event, {
    EventProvider? eventProvider,
    ExpenseProvider? expenseProvider,
  }) async {
    if (event.driveFileId == null || event.driveFileId!.isEmpty) return;

    _isSyncing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final db = await _databaseHelper.database;
      final selfPerson = await _peopleRepository.getSelfPerson();
      final authUser = await _authService.getCurrentUser();
      final selfPhone = (selfPerson?.phoneNumber != null && selfPerson!.phoneNumber.isNotEmpty)
          ? selfPerson.phoneNumber
          : (authUser?.phoneNumber ?? '');

      // 1. Download Master Trip Data
      final data = await _syncService.downloadTripData(event.driveFileId!);

      // Resolve effective folderId
      String folderId = '';
      if (data != null && data['folder_id'] != null && data['folder_id'].toString().isNotEmpty) {
        folderId = data['folder_id'].toString();
      } else if (data != null && data['resolved_folder_id'] != null && data['resolved_folder_id'].toString().isNotEmpty) {
        folderId = data['resolved_folder_id'].toString();
      } else if (event.driveFileId != null && event.driveFileId!.isNotEmpty) {
        folderId = event.driveFileId!;
      }

      // If remote returned updated folderId/driveFileId, update local event record
      if (folderId.isNotEmpty && folderId != event.driveFileId) {
        await db.update('events', {'drive_file_id': folderId}, where: 'id = ?', whereArgs: [event.id]);
        eventProvider?.refreshEventInList(event.id);
      }

      // Determine if this user is host
      bool isHost = false;
      if (authUser != null) {
        if (event.creatorId != null && event.creatorId == authUser.id) isHost = true;
        if (event.creatorEmail != null && event.creatorEmail == authUser.email) isHost = true;
        if (data != null && data['creator_id'] != null && data['creator_id'] == authUser.id) isHost = true;
        if (data != null && data['creator_email'] != null && data['creator_email'] == authUser.email) isHost = true;
      }
      if (!isHost && selfPhone.isNotEmpty) {
        if (data != null && data['creator_phone'] != null && PhoneHelper.isSamePhone(data['creator_phone'].toString(), selfPhone)) {
          isHost = true;
        } else if (data != null && data['members'] is List) {
          final hostMember = (data['members'] as List).cast<dynamic>().firstWhere(
            (m) => m is Map && (m['is_self'] == 1 || m['is_self'] == true),
            orElse: () => null,
          );
          if (hostMember != null && hostMember['phone_number'] != null &&
              PhoneHelper.isSamePhone(hostMember['phone_number'].toString(), selfPhone)) {
            isHost = true;
          }
        }
      }
      if (!isHost && selfPerson != null && data != null && data['members'] is List) {
        final hostMember = (data['members'] as List).cast<dynamic>().firstWhere(
          (m) => m is Map && (m['is_self'] == 1 || m['is_self'] == true),
          orElse: () => null,
        );
        if (hostMember != null && hostMember['id'] == selfPerson.id) {
          isHost = true;
        }
      }
      if (!isHost && selfPerson != null) {
        final localEventWithMembers = await _eventRepository.getEventById(event.id);
        if (localEventWithMembers != null) {
          for (final m in localEventWithMembers.members) {
            if (m.isSelf && selfPhone.isNotEmpty && m.phoneNumber.isNotEmpty && PhoneHelper.isSamePhone(m.phoneNumber, selfPhone)) {
              if (data != null && data['creator_phone'] != null && PhoneHelper.isSamePhone(data['creator_phone'].toString(), selfPhone)) {
                isHost = true;
                break;
              }
            }
          }
        }
      }

      // Determine myParticipantId
      String myParticipantId = selfPerson?.id ?? authUser?.id ?? 'p_${DateTime.now().millisecondsSinceEpoch}';
      if (selfPhone.isNotEmpty && data != null && data['members'] is List) {
        for (final m in data['members']) {
          if (m is Map) {
            final ph = m['phone_number']?.toString() ?? '';
            if (ph.isNotEmpty && PhoneHelper.isSamePhone(ph, selfPhone)) {
              final id = m['id']?.toString() ?? '';
              if (id.isNotEmpty) {
                myParticipantId = id;
                break;
              }
            }
          }
        }
      }
      if (myParticipantId == selfPerson?.id || myParticipantId.startsWith('p_')) {
        final eventWithMembers = await _eventRepository.getEventById(event.id);
        if (eventWithMembers != null) {
          final match = eventWithMembers.members.cast<PersonModel?>().firstWhere(
            (m) => m != null && m.phoneNumber.isNotEmpty && PhoneHelper.isSamePhone(m.phoneNumber, selfPhone),
            orElse: () => null,
          );
          if (match != null) {
            myParticipantId = match.id;
          }
        }
      }

      // 2. Sync members from Master Trip Data FIRST
      if (data != null) {
        final membersList = List<Map<String, dynamic>>.from(data['members'] ?? []);
        for (final m in membersList) {
          final p = PersonModel.fromMap(m);
          final bool isSelfMatch = selfPhone.isNotEmpty &&
              p.phoneNumber.isNotEmpty &&
              PhoneHelper.isSamePhone(selfPhone, p.phoneNumber);

          String resolvedName = p.name;
          if (isSelfMatch) {
            resolvedName = selfPerson?.name ?? p.name;
          } else if (p.phoneNumber.isNotEmpty) {
            final contactName = await _contactsService.findContactNameByPhone(p.phoneNumber);
            if (contactName != null && contactName.isNotEmpty) {
              resolvedName = contactName;
            }
          }

          final existing = await _peopleRepository.getPersonById(p.id);
          if (existing == null) {
            await db.insert(
              'people',
              p.copyWith(name: resolvedName, isSelf: isSelfMatch).toMap(),
            );
            if (isSelfMatch && selfPerson != null && selfPerson.id != p.id && selfPerson.phoneNumber.isEmpty) {
              await db.update('people', {'is_self': 0}, where: 'id = ?', whereArgs: [selfPerson.id]);
            }
          } else {
            final updateMap = <String, dynamic>{};
            if (isSelfMatch && !existing.isSelf) {
              updateMap['is_self'] = 1;
              if (selfPerson != null && selfPerson.id != p.id && selfPerson.phoneNumber.isEmpty) {
                await db.update('people', {'is_self': 0}, where: 'id = ?', whereArgs: [selfPerson.id]);
              }
            }
            if (resolvedName != p.name && resolvedName != existing.name) {
              updateMap['name'] = resolvedName;
            } else if (p.name.isNotEmpty && p.name != existing.name && !isSelfMatch) {
              final hasContactOverride = p.phoneNumber.isNotEmpty &&
                  (await _contactsService.findContactNameByPhone(p.phoneNumber)) != null;
              if (!hasContactOverride) {
                updateMap['name'] = p.name;
              }
            }
            if (p.upiId != null && p.upiId!.isNotEmpty && p.upiId != existing.upiId) {
              updateMap['upi_id'] = p.upiId;
            }
            if (p.phoneNumber.isNotEmpty && p.phoneNumber != existing.phoneNumber) {
              updateMap['phone_number'] = p.phoneNumber;
            }
            if (updateMap.isNotEmpty) {
              await db.update('people', updateMap, where: 'id = ?', whereArgs: [p.id]);
            }
          }
          await db.insert(
            'event_participants',
            {'event_id': event.id, 'person_id': p.id, 'count': p.count},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // 3. Fetch and merge participant patches from folder (Host only)
      if (isHost && folderId.isNotEmpty) {
        final patches = await _syncService.fetchParticipantPatches(folderId);
        for (final patch in patches) {
          final patchTripId = (patch['trip_id'] as String?) ?? event.id;
          final patchParticipantId = patch['participant_id'] as String?;
          final patchPhone = patch['phone_number'] as String?;

          // Ignore patches created by the Host itself
          if (patchPhone != null && patchPhone.isNotEmpty && selfPhone.isNotEmpty && PhoneHelper.isSamePhone(patchPhone, selfPhone)) {
            debugPrint('Host skipping own patch by phone: $patchPhone');
            continue;
          }
          if (patchParticipantId != null && (patchParticipantId == selfPerson?.id || (authUser != null && patchParticipantId == authUser.id))) {
            debugPrint('Host skipping own patch by ID: $patchParticipantId');
            continue;
          }

          final patchExpenses = List<Map<String, dynamic>>.from(patch['expenses'] ?? []);
          final patchExpenseIds = patchExpenses
              .map((e) => e['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();

          // Reconcile deletions for this participant:
          // Any expense in Host SQLite previously submitted or paid by this participant,
          // but NOT present in the participant's latest patch, was deleted!
          final currentLocalExpenses = await _expenseRepository.getExpensesForEvent(event.id);
          for (final localExp in currentLocalExpenses) {
            bool belongsToPatchParticipant = false;
            if (patchParticipantId != null && patchParticipantId.isNotEmpty) {
              if (localExp.payerId == patchParticipantId || localExp.submittedByPersonId == patchParticipantId) {
                belongsToPatchParticipant = true;
              }
            }
            if (!belongsToPatchParticipant && patchPhone != null && patchPhone.isNotEmpty) {
              final payer = await _peopleRepository.getPersonById(localExp.payerId);
              if (payer != null && payer.phoneNumber.isNotEmpty && PhoneHelper.isSamePhone(payer.phoneNumber, patchPhone)) {
                belongsToPatchParticipant = true;
              }
              if (!belongsToPatchParticipant && localExp.submittedByPersonId != null) {
                final submitter = await _peopleRepository.getPersonById(localExp.submittedByPersonId!);
                if (submitter != null && submitter.phoneNumber.isNotEmpty && PhoneHelper.isSamePhone(submitter.phoneNumber, patchPhone)) {
                  belongsToPatchParticipant = true;
                }
              }
            }

            if (belongsToPatchParticipant && !patchExpenseIds.contains(localExp.id)) {
              debugPrint('Host reconciling deletion: participant deleted ${localExp.id} (${localExp.title})');
              await _expenseRepository.deleteExpense(localExp.id);
            }
          }

          // Import / update expenses from patch
          for (final expMap in patchExpenses) {
            try {
              await _importExpenseRecord(
                db,
                patchTripId,
                expMap,
                patchParticipantId: patchParticipantId,
                patchPhone: patchPhone,
              );
            } catch (e) {
              debugPrint('Error parsing patch expense: $e');
            }
          }

          final participantId = patch['participant_id'] as String?;
          final patchUpi = patch['upi_id'] as String?;
          if (participantId != null && (patchUpi != null || patchPhone != null)) {
            final updateMap = <String, dynamic>{};
            if (patchUpi != null && patchUpi.isNotEmpty) updateMap['upi_id'] = patchUpi;
            if (patchPhone != null && patchPhone.isNotEmpty) updateMap['phone_number'] = patchPhone;
            if (updateMap.isNotEmpty) {
              await db.update('people', updateMap, where: 'id = ?', whereArgs: [participantId]);
            }
          }
        }
      }

      // 4. Sync approved and pending expenses from Master Trip Data (Participant only)
      if (!isHost && data != null) {
        final approvedList = List<Map<String, dynamic>>.from(data['approved_expenses'] ?? []);
        final pendingList = List<Map<String, dynamic>>.from(data['pending_expenses'] ?? []);
        final masterExpenseIds = [...approvedList, ...pendingList]
            .map((e) => e['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        // Reconcile deletions:
        // Any expense in SQLite that does NOT belong to this participant,
        // and is NOT in the Master file, was deleted by the Host / remote!
        final currentLocalExpenses = await _expenseRepository.getExpensesForEvent(event.id);
        for (final localExp in currentLocalExpenses) {
          bool isMyExpense = (myParticipantId.isNotEmpty &&
                  (localExp.payerId == myParticipantId || localExp.submittedByPersonId == myParticipantId)) ||
              (selfPerson != null &&
                  (localExp.payerId == selfPerson.id || localExp.submittedByPersonId == selfPerson.id));

          // Also check by phone number if available
          if (!isMyExpense && selfPhone.isNotEmpty) {
            final payer = await _peopleRepository.getPersonById(localExp.payerId);
            if (payer != null && PhoneHelper.isSamePhone(payer.phoneNumber, selfPhone)) {
              isMyExpense = true;
            }
            if (!isMyExpense && localExp.submittedByPersonId != null) {
              final submitter = await _peopleRepository.getPersonById(localExp.submittedByPersonId!);
              if (submitter != null && PhoneHelper.isSamePhone(submitter.phoneNumber, selfPhone)) {
                isMyExpense = true;
              }
            }
          }

          if (!isMyExpense && !masterExpenseIds.contains(localExp.id)) {
            debugPrint('Participant reconciling deletion: remote deleted ${localExp.id} (${localExp.title})');
            await _expenseRepository.deleteExpense(localExp.id);
          }
        }

        // Import approved and pending expenses from Master
        for (final expMap in [...approvedList, ...pendingList]) {
          try {
            await _importExpenseRecord(db, event.id, expMap);
          } catch (e) {
            debugPrint('Error parsing master expense: $e');
          }
        }
      }

      // 5. Bidirectional Sync: Push local updates to Drive
      if (isHost) {
        // Host pushes aggregated master data (including all merged local and patch expenses)
        final localExpenses = await _expenseRepository.getExpensesForEvent(event.id);
        final latestSettlements = await SettlementRepository().getSettlementsForEvent(event.id);
        final syncRes = await _syncService.shareTripToGoogleDrive(
          event: event.copyWith(
            driveFileId: folderId.isNotEmpty ? folderId : event.driveFileId,
            creatorId: event.creatorId ?? authUser?.id,
            creatorEmail: event.creatorEmail ?? authUser?.email,
          ),
          expenses: localExpenses,
          settlements: latestSettlements,
          creatorPhone: selfPhone,
        );
        if (syncRes.success && syncRes.driveFileId != null && syncRes.driveFileId!.isNotEmpty) {
          folderId = syncRes.driveFileId!;
          await db.update('events', {'drive_file_id': folderId}, where: 'id = ?', whereArgs: [event.id]);
        }
      } else if (folderId.isNotEmpty) {
        // Participant pushes ONLY their own expenses in the patch
        final localExpenses = await _expenseRepository.getExpensesForEvent(event.id);
        final myExpenses = <ExpenseModel>[];
        for (final e in localExpenses) {
          bool isMine = (myParticipantId.isNotEmpty && (e.payerId == myParticipantId || e.submittedByPersonId == myParticipantId)) ||
              (selfPerson != null && (e.payerId == selfPerson.id || e.submittedByPersonId == selfPerson.id));
          if (!isMine && selfPhone.isNotEmpty) {
            final payer = await _peopleRepository.getPersonById(e.payerId);
            if (payer != null && PhoneHelper.isSamePhone(payer.phoneNumber, selfPhone)) {
              isMine = true;
            }
            if (!isMine && e.submittedByPersonId != null) {
              final submitter = await _peopleRepository.getPersonById(e.submittedByPersonId!);
              if (submitter != null && PhoneHelper.isSamePhone(submitter.phoneNumber, selfPhone)) {
                isMine = true;
              }
            }
          }
          if (isMine) myExpenses.add(e);
        }

        await _syncService.pushParticipantPatch(
          folderId: folderId,
          eventId: event.id,
          participantId: myParticipantId,
          expenses: myExpenses,
          phoneNumber: selfPhone,
          upiId: selfPerson?.upiId,
        );
      }

      _lastSyncTime = DateTime.now();
      await _eventRepository.updateEventLastSyncedAt(event.id, _lastSyncTime);
      await loadPendingApprovals(event.id);
      if (expenseProvider != null) {
        await expenseProvider.loadForEvent(event.id);
      }
      if (eventProvider != null) {
        await eventProvider.refreshEventInList(event.id);
        await eventProvider.computeFinancials(event.id);
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _importExpenseRecord(
    Database db,
    String eventId,
    Map<String, dynamic> rawExpMap, {
    String? patchParticipantId,
    String? patchPhone,
  }) async {
    final expMap = Map<String, dynamic>.from(rawExpMap);
    if (expMap['event_id'] == null || expMap['event_id'].toString().isEmpty) {
      expMap['event_id'] = eventId;
    }

    final payerId = await _ensureValidPayerId(
      db,
      eventId,
      expMap,
      participantId: patchParticipantId,
      patchPhone: patchPhone,
    );
    expMap['payer_id'] = payerId;

    final exp = ExpenseModel.fromMap(expMap);
    await db.insert('expenses', exp.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

    if (exp.splits.isNotEmpty) {
      await db.delete('expense_splits', where: 'expense_id = ?', whereArgs: [exp.id]);
      for (final split in exp.splits) {
        await _ensurePersonExists(db, split.personId, eventId);
        await db.insert('expense_splits', split.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } else {
      final participants = await db.query('event_participants', where: 'event_id = ?', whereArgs: [eventId]);
      if (participants.isNotEmpty) {
        final totalCount = participants.fold<int>(0, (sum, p) => sum + ((p['count'] as int?) ?? 1));
        for (final p in participants) {
          final pid = p['person_id'] as String;
          final cnt = (p['count'] as int?) ?? 1;
          final alloc = totalCount > 0 ? (exp.amount * cnt / totalCount) : 0.0;
          final splitId = '${exp.id}_$pid';
          await db.insert('expense_splits', {
            'id': splitId,
            'expense_id': exp.id,
            'person_id': pid,
            'allocated_amount': alloc,
            'raw_value': alloc,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    }
  }

  Future<String> _ensureValidPayerId(
    Database db,
    String eventId,
    Map<String, dynamic> expMap, {
    String? participantId,
    String? patchPhone,
  }) async {
    String candidate = (expMap['payer_id'] ?? '').toString().trim();
    if (candidate.isEmpty && participantId != null && participantId.isNotEmpty) {
      candidate = participantId.trim();
    }
    if (candidate.isEmpty && expMap['submitted_by_person_id'] != null) {
      candidate = expMap['submitted_by_person_id'].toString().trim();
    }

    if (candidate.isNotEmpty) {
      final exists = (await db.query('people', where: 'id = ?', whereArgs: [candidate])).isNotEmpty;
      if (exists) return candidate;
    }

    final participants = await db.rawQuery('''
      SELECT p.id, p.name, p.phone_number, p.is_self
      FROM people p
      JOIN event_participants ep ON p.id = ep.person_id
      WHERE ep.event_id = ?
    ''', [eventId]);

    if (patchPhone != null && patchPhone.isNotEmpty) {
      for (final row in participants) {
        final ph = (row['phone_number'] ?? '').toString();
        if (ph.isNotEmpty && PhoneHelper.isSamePhone(ph, patchPhone)) {
          return row['id'] as String;
        }
      }
    }

    if (candidate.isNotEmpty) {
      for (final row in participants) {
        final ph = (row['phone_number'] ?? '').toString();
        if (ph.isNotEmpty && PhoneHelper.isSamePhone(ph, candidate)) {
          return row['id'] as String;
        }
      }
    }

    final submittedName = (expMap['submitted_by_name'] ?? '').toString().trim().toLowerCase();
    if (submittedName.isNotEmpty) {
      for (final row in participants) {
        final name = (row['name'] ?? '').toString().trim().toLowerCase();
        if (name.isNotEmpty && (name.contains(submittedName) || submittedName.contains(name))) {
          return row['id'] as String;
        }
      }
    }

    final nonSelf = participants.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row != null && ((row['is_self'] as int?) ?? 0) == 0,
      orElse: () => null,
    );
    if (nonSelf != null) {
      return nonSelf['id'] as String;
    }

    if (participants.isNotEmpty) {
      return participants.first['id'] as String;
    }

    final self = await _peopleRepository.getSelfPerson();
    if (self != null) return self.id;

    final fallbackId = candidate.isNotEmpty ? candidate : 'payer_${DateTime.now().millisecondsSinceEpoch}';
    await _ensurePersonExists(
      db,
      fallbackId,
      eventId,
      name: expMap['submitted_by_name']?.toString() ?? 'Member',
      phone: patchPhone,
    );
    return fallbackId;
  }

  Future<void> _ensurePersonExists(
    Database db,
    String personId,
    String eventId, {
    String? name,
    String? phone,
  }) async {
    final check = await db.query('people', where: 'id = ?', whereArgs: [personId]);
    if (check.isEmpty) {
      await db.insert('people', {
        'id': personId,
        'name': name ?? 'Member',
        'phone_number': phone ?? '',
        'is_self': 0,
        'count': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await db.insert('event_participants', {
      'event_id': eventId,
      'person_id': personId,
      'count': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
