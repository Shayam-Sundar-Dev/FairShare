import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/event_model.dart';
import '../models/person_model.dart';
import '../services/contacts_service.dart';
import '../../core/utils/phone_helper.dart';

class EventSummaryData {
  final double totalSpend;
  final int expenseCount;
  final int memberCount;

  const EventSummaryData({
    required this.totalSpend,
    required this.expenseCount,
    required this.memberCount,
  });
}

class EventRepository {
  final DatabaseHelper _databaseHelper;
  final Uuid _uuid = const Uuid();

  EventRepository({DatabaseHelper? databaseHelper})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  Future<List<EventModel>> getAllEvents() async {
    final db = await _databaseHelper.database;
    final eventMaps = await db.query(
      'events',
      orderBy: 'created_at DESC',
    );

    final List<EventModel> events = [];
    for (final map in eventMaps) {
      final eventId = map['id'] as String;
      final members = await _getEventMembers(db, eventId);
      events.add(EventModel.fromMap(map, members: members));
    }
    return events;
  }

  Future<EventModel?> getEventById(String id) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'events',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    final members = await _getEventMembers(db, id);
    return EventModel.fromMap(results.first, members: members);
  }

  Future<EventModel?> getEventByShareCode(String code) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'events',
      where: 'UPPER(share_code) = ?',
      whereArgs: [code.toUpperCase()],
      limit: 1,
    );
    if (results.isEmpty) return null;
    final members = await _getEventMembers(db, results.first['id'] as String);
    return EventModel.fromMap(results.first, members: members);
  }

  Future<EventModel?> getEventByDriveFileId(String fileId) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'events',
      where: 'drive_file_id = ?',
      whereArgs: [fileId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    final members = await _getEventMembers(db, results.first['id'] as String);
    return EventModel.fromMap(results.first, members: members);
  }

  Future<EventModel> createEvent({
    required String title,
    required String eventType,
    String currency = '₹',
    String description = '',
    required List<String> memberPersonIds,
    double estimatedBudget = 0.0,
    int installmentsCount = 1,
    String status = 'active',
    Map<String, int> memberCounts = const {},
    String? creatorId,
    String? creatorEmail,
    String? driveFileId,
    String? shareCode,
    bool isShared = false,
  }) async {
    final db = await _databaseHelper.database;
    final eventId = _uuid.v4();
    final event = EventModel(
      id: eventId,
      title: title,
      eventType: eventType,
      currency: currency,
      description: description,
      estimatedBudget: estimatedBudget,
      installmentsCount: installmentsCount,
      status: status,
      createdAt: DateTime.now(),
      isArchived: false,
      creatorId: creatorId,
      creatorEmail: creatorEmail,
      driveFileId: driveFileId,
      shareCode: shareCode,
      isShared: isShared,
    );

    await db.transaction((txn) async {
      await txn.insert('events', event.toMap());
      for (final personId in memberPersonIds.toSet()) {
        final count = memberCounts[personId] ?? 1;
        await txn.insert('event_participants', {
          'event_id': eventId,
          'person_id': personId,
          'count': count,
        });
      }
    });

    final members = await _getEventMembers(db, eventId);
    return event.copyWith(members: members);
  }

  Future<void> updateEvent({
    required EventModel event,
    required List<String> memberPersonIds,
    Map<String, int> memberCounts = const {},
  }) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        'events',
        event.toMap(),
        where: 'id = ?',
        whereArgs: [event.id],
      );

      // Re-assign members
      await txn.delete(
        'event_participants',
        where: 'event_id = ?',
        whereArgs: [event.id],
      );

      for (final personId in memberPersonIds.toSet()) {
        final count = memberCounts[personId] ?? 1;
        await txn.insert('event_participants', {
          'event_id': event.id,
          'person_id': personId,
          'count': count,
        });
      }
    });
  }

  Future<void> updateEventStatus(String id, String status) async {
    final db = await _databaseHelper.database;
    await db.update(
      'events',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateEventDriveSyncInfo({
    required String eventId,
    required String driveFileId,
    String? shareCode,
    bool isShared = true,
    DateTime? lastSyncedAt,
  }) async {
    final db = await _databaseHelper.database;
    final syncTime = lastSyncedAt ?? DateTime.now();
    final updateMap = <String, dynamic>{
      'drive_file_id': driveFileId,
      'is_shared': isShared ? 1 : 0,
      'last_synced_at': syncTime.millisecondsSinceEpoch,
    };
    if (shareCode != null) {
      updateMap['share_code'] = shareCode;
    }
    await db.update(
      'events',
      updateMap,
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> updateEventLastSyncedAt(String eventId, [DateTime? time]) async {
    final db = await _databaseHelper.database;
    final syncTime = time ?? DateTime.now();
    await db.update(
      'events',
      {
        'last_synced_at': syncTime.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> addMemberToEvent(String eventId, String personId, {int count = 1}) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'event_participants',
      {'event_id': eventId, 'person_id': personId, 'count': count},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> setEventArchived(String id, bool isArchived) async {
    final db = await _databaseHelper.database;
    await db.update(
      'events',
      {'is_archived': isArchived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteEvent(String id) async {
    final db = await _databaseHelper.database;
    await db.delete('events', where: 'id = ?', whereArgs: [id]);
  }

  Future<EventSummaryData> getEventSummary(String eventId) async {
    final db = await _databaseHelper.database;

    final expenseResult = await db.rawQuery('''
      SELECT COUNT(*) as count, COALESCE(SUM(amount), 0.0) as total
      FROM expenses
      WHERE event_id = ?
    ''', [eventId]);

    final memberResult = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM event_participants
      WHERE event_id = ?
    ''', [eventId]);

    final double totalSpend = (expenseResult.first['total'] as num).toDouble();
    final int expenseCount = (expenseResult.first['count'] as int);
    final int memberCount = (memberResult.first['count'] as int);

    return EventSummaryData(
      totalSpend: totalSpend,
      expenseCount: expenseCount,
      memberCount: memberCount,
    );
  }

  Future<List<PersonModel>> _getEventMembers(DatabaseExecutor db, String eventId) async {
    final selfResults = await db.query(
      'people',
      where: 'is_self = 1',
      limit: 1,
    );
    final PersonModel? self = selfResults.isNotEmpty ? PersonModel.fromMap(selfResults.first) : null;
    final selfPhone = self?.phoneNumber ?? '';
    final selfName = (self?.name ?? '').trim().toLowerCase();

    final results = await db.rawQuery('''
      SELECT p.*, COALESCE(ep.count, 1) as count FROM people p
      INNER JOIN event_participants ep ON p.id = ep.person_id
      WHERE ep.event_id = ?
      ORDER BY p.is_self DESC, p.name COLLATE NOCASE ASC
    ''', [eventId]);

    // Lookup device contacts to show members as per user's contact list
    final contactMap = await ContactsService().fetchDeviceContacts(requestIfMissing: false);
    final phoneToContactName = <String, String>{};
    for (final c in contactMap) {
      if (c.displayName.trim().isEmpty) continue;
      for (final ph in c.phoneNumbers) {
        final k = PhoneHelper.last10(ph);
        if (k.isNotEmpty) {
          phoneToContactName[k] = c.displayName.trim();
        }
      }
    }

    return results.map((m) {
      var p = PersonModel.fromMap(m);
      final pName = p.name.trim().toLowerCase();

      // Member is identified as self if phone number matches self or ID matches self
      final bool isMatchSelf = p.isSelf ||
          (self != null && p.id == self.id) ||
          (selfPhone.isNotEmpty && p.phoneNumber.isNotEmpty && PhoneHelper.isSamePhone(selfPhone, p.phoneNumber)) ||
          (selfName.isNotEmpty && selfName != 'you' && pName == selfName);

      if (isMatchSelf) {
        return p.copyWith(
          isSelf: true,
          phoneNumber: p.phoneNumber.isNotEmpty ? p.phoneNumber : (self?.phoneNumber ?? ''),
        );
      }

      // If not self, resolve member's display name as per user's contact list
      if (p.phoneNumber.isNotEmpty) {
        final key = PhoneHelper.last10(p.phoneNumber);
        final contactName = phoneToContactName[key];
        if (contactName != null && contactName.isNotEmpty) {
          p = p.copyWith(name: contactName);
        }
      }

      return p;
    }).toList();
  }
}
