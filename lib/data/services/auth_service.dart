import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/phone_helper.dart';
import '../models/user_model.dart';

class AuthService {
  static const String driveScope =
      'https://www.googleapis.com/auth/drive';
  static const String driveFileScope =
      'https://www.googleapis.com/auth/drive.file';

  static const List<String> driveScopes = [
    'email',
    'profile',
    driveScope,
    driveFileScope,
  ];

  static final AuthService _instance = AuthService._internal();

  factory AuthService({GoogleSignIn? googleSignIn}) {
    if (googleSignIn != null) {
      return AuthService._custom(googleSignIn);
    }
    return _instance;
  }

  AuthService._internal()
      : _googleSignIn = GoogleSignIn(
          scopes: driveScopes,
        );

  AuthService._custom(this._googleSignIn);

  final GoogleSignIn _googleSignIn;

  GoogleSignIn get googleSignIn => _googleSignIn;
  GoogleSignInAccount? get currentGoogleAccount => _googleSignIn.currentUser;
  bool get hasActiveGoogleSession => _googleSignIn.currentUser != null;

  Future<Map<String, String>?> getAuthHeaders() async {
    try {
      var account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      if (account == null) return null;
      return await account.authHeaders;
    } catch (_) {
      return null;
    }
  }

  Future<bool> ensureDriveScope() async {
    try {
      var account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      if (account == null) return false;

      try {
        final hasScope = await _googleSignIn.canAccessScopes([driveScope]);
        if (hasScope) return true;
        return await _googleSignIn.requestScopes([driveScope]);
      } on UnimplementedError {
        // Android GoogleSignIn plugin does not implement canAccessScopes.
        // Since GoogleSignIn was initialized with driveScopes, the active session includes it.
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  static const String _keyUserId = 'auth_user_id';
  static const String _keyDisplayName = 'auth_display_name';
  static const String _keyEmail = 'auth_email';
  static const String _keyPhotoUrl = 'auth_photo_url';
  static const String _keyPhoneNumber = 'auth_phone_number';
  static const String _keyIsGuest = 'auth_is_guest';
  static const String _keyProvider = 'auth_provider';

  Future<UserModel?> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        // User cancelled the sign-in flow
        return null;
      }

      final existingUser = await getSavedUser();
      final user = UserModel(
        id: account.id,
        displayName: account.displayName?.isNotEmpty == true
            ? account.displayName!
            : (account.email.split('@').first),
        email: account.email,
        photoUrl: account.photoUrl,
        phoneNumber: existingUser?.phoneNumber,
        isGuest: false,
        authProvider: 'google',
      );

      await _persistUser(user);
      return user;
    } catch (e) {
      rethrow;
    }
  }

  Future<UserModel?> signInSilently() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        final existingUser = await getSavedUser();
        final user = UserModel(
          id: account.id,
          displayName: account.displayName?.isNotEmpty == true
              ? account.displayName!
              : (account.email.split('@').first),
          email: account.email,
          photoUrl: account.photoUrl,
          phoneNumber: existingUser?.phoneNumber,
          isGuest: false,
          authProvider: 'google',
        );
        await _persistUser(user);
        return user;
      }
    } catch (_) {
      // Silent sign-in may fail or not be supported; fall back to saved local preferences
    }

    return await getSavedUser();
  }

  Future<UserModel> signInAsGuest() async {
    final user = UserModel(
      id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      displayName: 'Guest User',
      email: '',
      photoUrl: null,
      isGuest: true,
      authProvider: 'guest',
    );

    await _persistUser(user);
    return user;
  }

  Future<UserModel> signInWithDemoAccount({String? name, String? email}) async {
    final user = UserModel(
      id: 'demo_user_${DateTime.now().millisecondsSinceEpoch}',
      displayName: name?.isNotEmpty == true ? name! : 'Demo User',
      email: email?.isNotEmpty == true ? email! : 'demo@fairshare.app',
      photoUrl: null,
      isGuest: false,
      authProvider: 'demo',
    );

    await _persistUser(user);
    return user;
  }

  Future<void> signOut({String? provider}) async {
    // 1. Remove local saved credentials first to guarantee local sign-out
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyUserId);
      await prefs.remove(_keyDisplayName);
      await prefs.remove(_keyEmail);
      await prefs.remove(_keyPhotoUrl);
      await prefs.remove(_keyPhoneNumber);
      await prefs.remove(_keyIsGuest);
      await prefs.remove(_keyProvider);
    } catch (_) {
      // Non-fatal if local prefs fail
    }

    // 2. Only disconnect from Google SDK if provider is explicitly google
    if (provider == 'google') {
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Best effort - never block local logout
      }
    }
  }

  Future<UserModel?> getCurrentUser() => getSavedUser();

  Future<UserModel?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keyUserId);
    if (id == null) return null;

    final displayName = prefs.getString(_keyDisplayName) ?? 'User';
    final email = prefs.getString(_keyEmail) ?? '';
    final photoUrl = prefs.getString(_keyPhotoUrl);
    var phoneNumber = prefs.getString(_keyPhoneNumber);
    if (phoneNumber == null || phoneNumber.trim().isEmpty) {
      final upi = prefs.getString('user_upi_id') ?? '';
      final upiPhone = PhoneHelper.extractPhoneFromUpi(upi);
      if (upiPhone.isNotEmpty) {
        phoneNumber = upiPhone;
        await prefs.setString(_keyPhoneNumber, upiPhone);
      }
    }
    final isGuest = prefs.getBool(_keyIsGuest) ?? false;
    final provider = prefs.getString(_keyProvider) ?? 'google';

    return UserModel(
      id: id,
      displayName: displayName,
      email: email,
      photoUrl: photoUrl,
      phoneNumber: phoneNumber,
      isGuest: isGuest,
      authProvider: provider,
    );
  }

  Future<void> updatePhoneNumber(String phoneNumber) async {
    final prefs = await SharedPreferences.getInstance();
    if (phoneNumber.trim().isNotEmpty) {
      await prefs.setString(_keyPhoneNumber, phoneNumber.trim());
    } else {
      await prefs.remove(_keyPhoneNumber);
    }
  }

  Future<void> _persistUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, user.id);
    await prefs.setString(_keyDisplayName, user.displayName);
    await prefs.setString(_keyEmail, user.email);
    if (user.photoUrl != null) {
      await prefs.setString(_keyPhotoUrl, user.photoUrl!);
    } else {
      await prefs.remove(_keyPhotoUrl);
    }
    if (user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty) {
      await prefs.setString(_keyPhoneNumber, user.phoneNumber!.trim());
    } else if (user.phoneNumber != null && user.phoneNumber!.trim().isEmpty) {
      await prefs.remove(_keyPhoneNumber);
    }
    await prefs.setBool(_keyIsGuest, user.isGuest);
    await prefs.setString(_keyProvider, user.authProvider);
  }
}
