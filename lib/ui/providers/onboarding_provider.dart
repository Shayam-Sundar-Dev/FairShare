import 'package:flutter/foundation.dart';
import '../../data/services/permission_service.dart';

class OnboardingProvider extends ChangeNotifier {
  final PermissionService _permissionService;

  bool _isLoading = true;
  bool _isOnboardingCompleted = false;
  bool _isRequestingAll = false;
  final Map<AppPermissionItem, bool> _permissionStatus = {
    AppPermissionItem.contacts: false,
    AppPermissionItem.camera: false,
    AppPermissionItem.photos: false,
    AppPermissionItem.location: false,
  };

  OnboardingProvider({PermissionService? permissionService})
      : _permissionService = permissionService ?? PermissionService() {
    checkStatus();
  }

  bool get isLoading => _isLoading;
  bool get isOnboardingCompleted => _isOnboardingCompleted;
  bool get isRequestingAll => _isRequestingAll;
  Map<AppPermissionItem, bool> get permissionStatus =>
      Map.unmodifiable(_permissionStatus);

  bool get allPermissionsGranted =>
      _permissionStatus.values.isNotEmpty &&
      _permissionStatus.values.every((granted) => granted);

  int get grantedCount =>
      _permissionStatus.values.where((granted) => granted).length;

  int get totalCount => _permissionStatus.length;

  /// Check initial onboarding completion status and device permissions.
  Future<void> checkStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      _isOnboardingCompleted =
          await _permissionService.isOnboardingCompleted();
      await refreshPermissions(notify: false);
    } catch (e) {
      debugPrint('OnboardingProvider: error checking status: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh current permission grant states from the device OS.
  Future<void> refreshPermissions({bool notify = true}) async {
    for (final item in AppPermissionItem.values) {
      final granted = await _permissionService.isGranted(item);
      _permissionStatus[item] = granted;
    }
    if (notify) {
      notifyListeners();
    }
  }

  /// Request access for an individual permission item.
  Future<bool> requestPermission(AppPermissionItem item) async {
    try {
      final granted = await _permissionService.request(item);
      _permissionStatus[item] = granted;
      notifyListeners();
      return granted;
    } catch (e) {
      debugPrint('OnboardingProvider: failed requesting $item: $e');
      return false;
    }
  }

  /// Sequentially request all 4 permissions with real-time UI feedback.
  Future<void> requestAllPermissions() async {
    if (_isRequestingAll) return;
    _isRequestingAll = true;
    notifyListeners();

    try {
      for (final item in AppPermissionItem.values) {
        if (_permissionStatus[item] != true) {
          final granted = await _permissionService.request(item);
          _permissionStatus[item] = granted;
          notifyListeners();
          // Small breathing room between system OS prompts
          await Future.delayed(const Duration(milliseconds: 250));
        }
      }
    } finally {
      _isRequestingAll = false;
      notifyListeners();
    }
  }

  /// Mark onboarding as completed and persist to SharedPreferences.
  Future<void> completeOnboarding() async {
    _isOnboardingCompleted = true;
    notifyListeners();
    await _permissionService.setOnboardingCompleted(completed: true);
  }

  /// Reset onboarding state (useful for testing or reviewing permissions).
  Future<void> resetOnboarding() async {
    _isOnboardingCompleted = false;
    notifyListeners();
    await _permissionService.setOnboardingCompleted(completed: false);
    await checkStatus();
  }

  /// Open device app settings.
  Future<void> openSettings() async {
    await _permissionService.openAppSettingsPage();
  }
}
