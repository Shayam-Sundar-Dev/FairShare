import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' hide PermissionStatus;
import 'package:shared_preferences/shared_preferences.dart';

enum AppPermissionItem {
  contacts,
  camera,
  photos,
  location,
}

class PermissionService {
  static const String keyOnboardingCompleted = 'has_completed_onboarding_v1';

  /// Check whether the first-time onboarding / get started flow has been completed.
  Future<bool> isOnboardingCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(keyOnboardingCompleted) == true) {
        return true;
      }
      // If user has an existing account, onboarding is already completed
      if (prefs.getString('auth_user_id') != null) {
        await prefs.setBool(keyOnboardingCompleted, true);
        return true;
      }
      // If permissions are already active on the device, mark as completed
      final contacts = await isGranted(AppPermissionItem.contacts);
      final camera = await isGranted(AppPermissionItem.camera);
      final photos = await isGranted(AppPermissionItem.photos);
      final location = await isGranted(AppPermissionItem.location);
      if ((contacts && camera) || (photos && location) || (contacts && photos) || (contacts || camera || photos || location)) {
        // If at least contacts/camera/photos/location are granted, mark completed
        await prefs.setBool(keyOnboardingCompleted, true);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Mark the onboarding flow as completed.
  Future<void> setOnboardingCompleted({bool completed = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyOnboardingCompleted, completed);
    } catch (e) {
      debugPrint('PermissionService: failed to save onboarding flag: $e');
    }
  }

  /// Check the current granted status of an individual permission.
  Future<bool> isGranted(AppPermissionItem item) async {
    try {
      switch (item) {
        case AppPermissionItem.contacts:
          try {
            return await FlutterContacts.permissions.has(PermissionType.read);
          } catch (_) {
            return await Permission.contacts.isGranted;
          }

        case AppPermissionItem.camera:
          return await Permission.camera.isGranted;

        case AppPermissionItem.photos:
          if (!kIsWeb && Platform.isAndroid) {
            final photos = await Permission.photos.isGranted;
            final storage = await Permission.storage.isGranted;
            return photos || storage;
          }
          return await Permission.photos.isGranted;

        case AppPermissionItem.location:
          try {
            final loc = await Geolocator.checkPermission();
            return loc == LocationPermission.always ||
                loc == LocationPermission.whileInUse;
          } catch (_) {
            return await Permission.locationWhenInUse.isGranted;
          }
      }
    } catch (e) {
      debugPrint('PermissionService: error checking $item: $e');
      return false;
    }
  }

  /// Request access for a specific permission item.
  Future<bool> request(AppPermissionItem item) async {
    try {
      switch (item) {
        case AppPermissionItem.contacts:
          try {
            final status =
                await FlutterContacts.permissions.request(PermissionType.read);
            return status == PermissionStatus.granted;
          } catch (_) {
            final res = await Permission.contacts.request();
            return res.isGranted;
          }

        case AppPermissionItem.camera:
          final res = await Permission.camera.request();
          return res.isGranted;

        case AppPermissionItem.photos:
          if (!kIsWeb && Platform.isAndroid) {
            var res = await Permission.photos.request();
            if (!res.isGranted) {
              res = await Permission.storage.request();
            }
            return res.isGranted;
          }
          final res = await Permission.photos.request();
          return res.isGranted;

        case AppPermissionItem.location:
          try {
            var perm = await Geolocator.checkPermission();
            if (perm == LocationPermission.denied) {
              perm = await Geolocator.requestPermission();
            }
            return perm == LocationPermission.always ||
                perm == LocationPermission.whileInUse;
          } catch (_) {
            final res = await Permission.locationWhenInUse.request();
            return res.isGranted;
          }
      }
    } catch (e) {
      debugPrint('PermissionService: error requesting $item: $e');
      return false;
    }
  }

  /// Request all 4 permissions sequentially.
  Future<Map<AppPermissionItem, bool>> requestAll() async {
    final results = <AppPermissionItem, bool>{};
    for (final item in AppPermissionItem.values) {
      results[item] = await request(item);
    }
    return results;
  }

  /// Open app settings page if user previously permanently denied permissions.
  Future<bool> openAppSettingsPage() async {
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }
}
