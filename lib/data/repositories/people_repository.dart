import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/person_model.dart';
import '../services/auth_service.dart';
import '../../core/utils/phone_helper.dart';

class PeopleRepository {
  final DatabaseHelper _databaseHelper;
  final Uuid _uuid = const Uuid();

  PeopleRepository({DatabaseHelper? databaseHelper})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  Future<List<PersonModel>> getAllPeople() async {
    final db = await _databaseHelper.database;
    final self = await getSelfPerson();

    final results = await db.query(
      'people',
      orderBy: 'is_self DESC, name COLLATE NOCASE ASC',
    );

    final List<PersonModel> list = [];
    final Set<String> seenIds = {};

    for (final m in results) {
      final person = PersonModel.fromMap(m);
      if (seenIds.contains(person.id)) continue;

      // Don't show duplicate 'You' in the friends list
      if (self != null && !person.isSelf) {
        final bool isDuplicatePhone = PhoneHelper.isSamePhone(self.phoneNumber, person.phoneNumber);
        final bool isDuplicateContactId =
            person.contactId != null && person.contactId!.isNotEmpty && person.contactId == self.contactId;
        final bool isStaleYouName = person.name.trim().toLowerCase() == 'you';

        if (isDuplicatePhone || isDuplicateContactId || isStaleYouName) {
          continue;
        }
      }

      seenIds.add(person.id);
      list.add(person);
    }
    return list;
  }

  Future<PersonModel?> getPersonById(String id) async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'people',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return PersonModel.fromMap(results.first);
  }

  Future<PersonModel?> getPersonByPhone(String phoneNumber) async {
    final clean = PhoneHelper.clean(phoneNumber);
    if (clean.isEmpty) return null;
    final db = await _databaseHelper.database;
    final results = await db.query(
      'people',
      where: "phone_number IS NOT NULL AND phone_number != ''",
    );
    for (final row in results) {
      final p = PersonModel.fromMap(row);
      if (PhoneHelper.isSamePhone(p.phoneNumber, phoneNumber)) {
        return p;
      }
    }
    return null;
  }

  Future<PersonModel?> getSelfPerson() async {
    final db = await _databaseHelper.database;
    final results = await db.query(
      'people',
      where: 'is_self = 1',
      orderBy: 'rowid ASC',
    );

    if (results.isNotEmpty) {
      final resultsList = List<Map<String, dynamic>>.from(results);
      if (resultsList.length > 1) {
        // Sort to ensure the most complete profile is chosen as primary 'self'
        // (prefer non-default name, non-empty phone number, non-empty UPI ID)
        resultsList.sort((a, b) {
          final aName = (a['name'] as String? ?? '').trim().toLowerCase();
          final bName = (b['name'] as String? ?? '').trim().toLowerCase();
          final aPhone = (a['phone_number'] as String? ?? '').trim();
          final bPhone = (b['phone_number'] as String? ?? '').trim();
          final aUpi = (a['upi_id'] as String? ?? '').trim();
          final bUpi = (b['upi_id'] as String? ?? '').trim();

          final aScore = (aName.isNotEmpty && aName != 'you' ? 3 : 0) +
              (aPhone.isNotEmpty ? 2 : 0) +
              (aUpi.isNotEmpty ? 2 : 0);
          final bScore = (bName.isNotEmpty && bName != 'you' ? 3 : 0) +
              (bPhone.isNotEmpty ? 2 : 0) +
              (bUpi.isNotEmpty ? 2 : 0);

          return bScore.compareTo(aScore);
        });

        final self = PersonModel.fromMap(resultsList.first);
        for (int i = 1; i < resultsList.length; i++) {
          final dupId = resultsList[i]['id'] as String;
          await db.execute(
            'UPDATE OR IGNORE event_participants SET person_id = ? WHERE person_id = ?',
            [self.id, dupId],
          );
          await db.execute(
            'UPDATE expenses SET payer_id = ? WHERE payer_id = ?',
            [self.id, dupId],
          );
          await db.execute(
            'UPDATE expense_splits SET person_id = ? WHERE person_id = ?',
            [self.id, dupId],
          );
          await db.execute(
            'UPDATE settlements SET payer_id = ? WHERE payer_id = ?',
            [self.id, dupId],
          );
          await db.execute(
            'UPDATE settlements SET payee_id = ? WHERE payee_id = ?',
            [self.id, dupId],
          );
          await db.delete('people', where: 'id = ?', whereArgs: [dupId]);
        }
        return self;
      }

      var self = PersonModel.fromMap(results.first);
      if (self.phoneNumber.trim().isEmpty) {
        final authUser = await AuthService().getCurrentUser();
        final authPhone = authUser?.phoneNumber?.trim() ?? '';
        if (authPhone.isNotEmpty) {
          final matches = await db.query('people', where: 'phone_number IS NOT NULL AND phone_number != ""');
          final matchingRow = matches.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r != null && PhoneHelper.isSamePhone(r['phone_number'] as String?, authPhone),
            orElse: () => null,
          );
          if (matchingRow != null) {
            final matchId = matchingRow['id'] as String;
            if (matchId != self.id) {
              await db.update('people', {'is_self': 1}, where: 'id = ?', whereArgs: [matchId]);
              await db.delete('people', where: 'id = ?', whereArgs: [self.id]);
              return PersonModel.fromMap(matchingRow).copyWith(isSelf: true);
            }
          }
          self = self.copyWith(phoneNumber: authPhone);
          await db.update('people', {'phone_number': authPhone}, where: 'id = ?', whereArgs: [self.id]);
        }
      }
      return self;
    }

    // Automatically create default 'You' if not present
    final authUser = await AuthService().getCurrentUser();
    final authPhone = authUser?.phoneNumber?.trim() ?? '';
    final authName = authUser?.displayName.trim() ?? 'You';

    if (authPhone.isNotEmpty) {
      final matches = await db.query('people', where: 'phone_number IS NOT NULL AND phone_number != ""');
      final matchingRow = matches.cast<Map<String, dynamic>?>().firstWhere(
        (r) => r != null && PhoneHelper.isSamePhone(r['phone_number'] as String?, authPhone),
        orElse: () => null,
      );
      if (matchingRow != null) {
        final matchId = matchingRow['id'] as String;
        await db.update('people', {'is_self': 1}, where: 'id = ?', whereArgs: [matchId]);
        return PersonModel.fromMap(matchingRow).copyWith(isSelf: true);
      }
    }

    final self = PersonModel(
      id: _uuid.v4(),
      name: authName.isNotEmpty ? authName : 'You',
      phoneNumber: authPhone,
      isSelf: true,
      avatarColor: '0xFF1E56A0',
    );
    await db.insert('people', self.toMap());
    return self;
  }

  Future<void> updateSelfPerson({required String name, String? phoneNumber, String? upiId}) async {
    final db = await _databaseHelper.database;
    final self = await getSelfPerson();
    if (self != null) {
      final values = <String, dynamic>{
        'name': name.trim().isEmpty ? 'You' : name.trim(),
      };
      if (phoneNumber != null) {
        values['phone_number'] = phoneNumber.trim();
      }
      if (upiId != null) {
        values['upi_id'] = upiId.trim();
      }
      await db.update(
        'people',
        values,
        where: 'id = ?',
        whereArgs: [self.id],
      );
    }
  }

  Future<PersonModel> createOrFindPerson({
    required String name,
    required String phoneNumber,
    String? contactId,
    String? avatarColor,
    String? upiId,
  }) async {
    final db = await _databaseHelper.database;
    final self = await getSelfPerson();


    // If matching self user's phone or contactId, update and return self
    if (self != null) {
      final bool isSelfPhoneMatch = PhoneHelper.isSamePhone(self.phoneNumber, phoneNumber);
      final bool isSelfContactMatch =
          contactId != null && contactId.isNotEmpty && self.contactId == contactId;
      final bool isSelfNameMatch =
          name.trim().toLowerCase() == 'you' ||
          (self.name.toLowerCase() != 'you' && name.trim().toLowerCase() == self.name.toLowerCase());

      if (isSelfPhoneMatch || isSelfContactMatch || (isSelfNameMatch && self.phoneNumber.isEmpty)) {
        await db.update(
          'people',
          {
            if (name.trim().isNotEmpty && name.trim().toLowerCase() != 'you') 'name': name.trim(),
            if (phoneNumber.trim().isNotEmpty) 'phone_number': phoneNumber.trim(),
            if (contactId != null && contactId.isNotEmpty) 'contact_id': contactId,
            'avatar_color': ?avatarColor,
            if (upiId != null && upiId.isNotEmpty) 'upi_id': upiId.trim(),
          },
          where: 'id = ?',
          whereArgs: [self.id],
        );
        return (await getPersonById(self.id)) ?? self;
      }
    }

    // Check if person exists by phone number (if non-empty) or by contactId
    if (phoneNumber.isNotEmpty) {
      final existingByPhone = await getPersonByPhone(phoneNumber);
      if (existingByPhone != null) {
        return existingByPhone;
      }
    }

    if (contactId != null && contactId.isNotEmpty) {
      final existingByContact = await db.query(
        'people',
        where: 'contact_id = ?',
        whereArgs: [contactId],
        limit: 1,
      );
      if (existingByContact.isNotEmpty) {
        return PersonModel.fromMap(existingByContact.first);
      }
    }

    // Check by exact name match if phone is empty
    if (phoneNumber.isEmpty) {
      final existingByName = await db.query(
        'people',
        where: "name = ? COLLATE NOCASE AND is_self = 0",
        whereArgs: [name.trim()],
        limit: 1,
      );
      if (existingByName.isNotEmpty) {
        return PersonModel.fromMap(existingByName.first);
      }
    }

    final newPerson = PersonModel(
      id: _uuid.v4(),
      name: name.trim(),
      phoneNumber: phoneNumber.trim(),
      contactId: contactId,
      avatarColor: avatarColor,
      isSelf: false,
      upiId: upiId,
    );

    await db.insert('people', newPerson.toMap());
    return newPerson;
  }

  Future<void> updatePerson(PersonModel person) async {
    final db = await _databaseHelper.database;
    await db.update(
      'people',
      person.toMap(),
      where: 'id = ?',
      whereArgs: [person.id],
    );
  }

  Future<void> deletePerson(String id) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'people',
      where: 'id = ? AND is_self = 0',
      whereArgs: [id],
    );
  }

  Future<List<PersonModel>> getMembersForEvent(String eventId) async {
    final db = await _databaseHelper.database;
    final results = await db.rawQuery('''
      SELECT p.* FROM people p
      INNER JOIN event_participants ep ON p.id = ep.person_id
      WHERE ep.event_id = ?
      ORDER BY p.is_self DESC, p.name COLLATE NOCASE ASC
    ''', [eventId]);

    return results.map((m) => PersonModel.fromMap(m)).toList();
  }
}
