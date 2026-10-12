import 'package:flutter_contacts/flutter_contacts.dart';
import '../../core/utils/phone_helper.dart';

class DeviceContactItem {
  final String id;
  final String displayName;
  final List<String> phoneNumbers;
  final String? email;

  const DeviceContactItem({
    required this.id,
    required this.displayName,
    required this.phoneNumbers,
    this.email,
  });
}

class ContactsService {
  static Map<String, String>? _cachedPhoneToNameMap;
  static List<DeviceContactItem>? _cachedContacts;
  static DateTime? _cacheTimestamp;

  Future<bool> requestPermission() async {
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      return status == PermissionStatus.granted;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    try {
      return await FlutterContacts.permissions.has(PermissionType.read);
    } catch (_) {
      return false;
    }
  }

  Future<List<DeviceContactItem>> fetchDeviceContacts({bool requestIfMissing = true}) async {
    try {
      final permitted = await FlutterContacts.permissions.has(PermissionType.read);
      if (!permitted) {
        if (!requestIfMissing) return [];
        final status = await FlutterContacts.permissions.request(PermissionType.read);
        if (status != PermissionStatus.granted) return [];
      }

      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone, ContactProperty.email},
      );

      final List<DeviceContactItem> result = [];
      final phoneMap = <String, String>{};

      for (final contact in contacts) {
        final name = contact.displayName?.trim() ?? '';
        if (name.isEmpty) continue;

        final phoneNumbers = contact.phones
            .map((p) => p.number.replaceAll(RegExp(r'[\s\-()]'), ''))
            .where((cleanNumber) => cleanNumber.isNotEmpty)
            .toSet()
            .toList();

        result.add(DeviceContactItem(
          id: contact.id ?? '',
          displayName: name,
          phoneNumbers: phoneNumbers,
          email: contact.emails.isNotEmpty ? contact.emails.first.address : null,
        ));

        for (final p in phoneNumbers) {
          final k = PhoneHelper.last10(p);
          if (k.isNotEmpty) {
            phoneMap[k] = name;
          }
        }
      }

      result.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      _cachedContacts = result;
      _cachedPhoneToNameMap = phoneMap;
      _cacheTimestamp = DateTime.now();
      return result;
    } catch (e) {
      return [];
    }
  }

  /// Looks up the device contact's display name for a given phone number.
  /// Does not force a permission popup if permission has not been granted.
  Future<String?> findContactNameByPhone(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.trim().isEmpty) return null;
    final key = PhoneHelper.last10(phoneNumber);
    if (key.isEmpty) return null;

    if (_cachedPhoneToNameMap != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < const Duration(minutes: 5)) {
      final found = _cachedPhoneToNameMap![key];
      if (found != null) return found;
    }

    final contacts = await fetchDeviceContacts(requestIfMissing: false);
    for (final contact in contacts) {
      for (final phone in contact.phoneNumbers) {
        if (PhoneHelper.isSamePhone(phone, phoneNumber)) {
          return contact.displayName;
        }
      }
    }
    return null;
  }

  /// Finds the DeviceContactItem matching a phone number
  Future<DeviceContactItem?> findContactByPhone(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.trim().isEmpty) return null;
    final contacts = _cachedContacts ?? await fetchDeviceContacts(requestIfMissing: false);
    for (final contact in contacts) {
      for (final phone in contact.phoneNumbers) {
        if (PhoneHelper.isSamePhone(phone, phoneNumber)) {
          return contact;
        }
      }
    }
    return null;
  }
}
