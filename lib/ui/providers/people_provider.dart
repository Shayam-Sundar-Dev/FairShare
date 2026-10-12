import 'package:flutter/material.dart';
import '../../core/utils/avatar_helper.dart';
import '../../data/models/person_model.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/services/contacts_service.dart';

class PeopleProvider extends ChangeNotifier {
  final PeopleRepository _peopleRepository;
  final ContactsService _contactsService;

  List<PersonModel> _people = [];
  List<DeviceContactItem> _deviceContacts = [];
  PersonModel? _selfPerson;
  bool _isLoading = false;
  bool _isContactsLoading = false;
  bool _hasContactPermission = false;
  String? _errorMessage;

  PeopleProvider({
    PeopleRepository? peopleRepository,
    ContactsService? contactsService,
  })  : _peopleRepository = peopleRepository ?? PeopleRepository(),
        _contactsService = contactsService ?? ContactsService();

  List<PersonModel> get people => _people;
  List<DeviceContactItem> get deviceContacts => _deviceContacts;
  PersonModel? get selfPerson => _selfPerson;
  bool get isLoading => _isLoading;
  bool get isContactsLoading => _isContactsLoading;
  bool get hasContactPermission => _hasContactPermission;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _selfPerson = await _peopleRepository.getSelfPerson();
      _people = await _peopleRepository.getAllPeople();
      _hasContactPermission = await _contactsService.hasPermission();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPeople() async {
    try {
      _people = await _peopleRepository.getAllPeople();
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<PersonModel> addPerson({
    required String name,
    required String phoneNumber,
    String? contactId,
  }) async {
    final avatarColor = AvatarHelper.getColorForName(name).toARGB32().toRadixString(16);
    final person = await _peopleRepository.createOrFindPerson(
      name: name,
      phoneNumber: phoneNumber,
      contactId: contactId,
      avatarColor: '0x$avatarColor',
    );
    await loadPeople();
    return person;
  }

  Future<void> deletePerson(String id) async {
    await _peopleRepository.deletePerson(id);
    await loadPeople();
  }

  Future<void> loadDeviceContacts() async {
    _isContactsLoading = true;
    notifyListeners();

    try {
      final permitted = await _contactsService.requestPermission();
      _hasContactPermission = permitted;
      if (permitted) {
        _deviceContacts = await _contactsService.fetchDeviceContacts();
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isContactsLoading = false;
      notifyListeners();
    }
  }

  Future<PersonModel> importFromContact(DeviceContactItem contact) async {
    final phone = contact.phoneNumbers.isNotEmpty ? contact.phoneNumbers.first : '';
    return await addPerson(
      name: contact.displayName,
      phoneNumber: phone,
      contactId: contact.id,
    );
  }

  Future<List<PersonModel>> importMultipleContacts(List<DeviceContactItem> contacts) async {
    final imported = <PersonModel>[];
    for (final contact in contacts) {
      final phone = contact.phoneNumbers.isNotEmpty ? contact.phoneNumbers.first : '';
      final avatarColor = AvatarHelper.getColorForName(contact.displayName).toARGB32().toRadixString(16);
      final person = await _peopleRepository.createOrFindPerson(
        name: contact.displayName,
        phoneNumber: phone,
        contactId: contact.id,
        avatarColor: '0x$avatarColor',
      );
      imported.add(person);
    }
    await loadPeople();
    return imported;
  }

  Future<void> updatePerson(PersonModel person) async {
    await _peopleRepository.updatePerson(person);
    await loadPeople();
  }

  Future<void> updateSelfPerson({String? name, String? phoneNumber, String? upiId}) async {
    final self = _selfPerson ?? await _peopleRepository.getSelfPerson();
    final updatedName = name ?? self?.name ?? 'You';
    final updatedPhone = phoneNumber ?? self?.phoneNumber ?? '';
    final updatedUpi = upiId ?? self?.upiId;
    await _peopleRepository.updateSelfPerson(
      name: updatedName,
      phoneNumber: updatedPhone,
      upiId: updatedUpi,
    );
    _selfPerson = await _peopleRepository.getSelfPerson();
    await loadPeople();
    notifyListeners();
  }
}
