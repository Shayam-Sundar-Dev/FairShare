import 'package:flutter/material.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final PeopleRepository _peopleRepository;

  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isInitialized = false;
  String? _errorMessage;

  AuthProvider({
    AuthService? authService,
    PeopleRepository? peopleRepository,
  })  : _authService = authService ?? AuthService(),
        _peopleRepository = peopleRepository ?? PeopleRepository() {
    initialize();
  }

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isGuest => _currentUser?.isGuest ?? false;
  bool get isGoogleSessionActive => _authService.hasActiveGoogleSession;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.signInSilently();
      if (_currentUser != null && !_currentUser!.isGuest) {
        await _syncSelfPerson(_currentUser!);
      }
    } catch (e) {
      _errorMessage = 'Failed to restore session: $e';
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithGoogle();
      if (user != null) {
        _currentUser = user;
        await _syncSelfPerson(user);
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _isLoading = false;
      notifyListeners();
      return false; // User cancelled
    } catch (e) {
      final err = e.toString();
      if (err.contains('channel-error') || err.contains('pigeon')) {
        _errorMessage = 'Full app restart required: stop and re-run the app to compile new Google Sign-In native plugins.';
      } else if (err.contains('ApiException: 10') || err.contains(': 10')) {
        _errorMessage = 'Google Sign-In configuration error: Android debug SHA-1 not registered in Google Cloud Console. Try using the Demo Account below.';
      } else {
        _errorMessage = 'Google Sign-In failed: $e';
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signInAsGuest() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInAsGuest();
      _currentUser = user;
    } catch (e) {
      _errorMessage = 'Guest Sign-In failed: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithDemoAccount({String? name, String? email}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithDemoAccount(name: name, email: email);
      _currentUser = user;
      await _syncSelfPerson(user);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Sign-In failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      final currentProvider = _currentUser?.authProvider;
      await _authService.signOut(provider: currentProvider);
    } catch (e) {
      _errorMessage = 'Sign-Out notice: $e';
    } finally {
      _currentUser = null;
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    }
  }

  Future<void> updatePhoneNumber(String phoneNumber) async {
    final phone = phoneNumber.trim();
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(phoneNumber: phone);
    }
    await _authService.updatePhoneNumber(phone);
    try {
      if (_currentUser != null) {
        await _peopleRepository.updateSelfPerson(
          name: _currentUser!.displayName,
          phoneNumber: phone,
        );
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _syncSelfPerson(UserModel user) async {
    try {
      if (user.displayName.isNotEmpty) {
        await _peopleRepository.updateSelfPerson(
          name: user.displayName,
          phoneNumber: user.phoneNumber,
        );
      }
    } catch (_) {
      // Non-fatal if local db sync encounters an edge case
    }
  }
}
