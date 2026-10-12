class UserModel {
  final String id;
  final String displayName;
  final String email;
  final String? photoUrl;
  final String? phoneNumber;
  final bool isGuest;
  final String authProvider; // 'google' or 'guest'

  const UserModel({
    required this.id,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.phoneNumber,
    this.isGuest = false,
    this.authProvider = 'google',
  });

  bool get isDemo =>
      authProvider == 'demo' ||
      id.startsWith('demo_') ||
      id.startsWith('google_user_') ||
      email == 'demo@fairshare.app' ||
      email == 'user@gmail.com';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'phoneNumber': phoneNumber,
      'isGuest': isGuest ? 1 : 0,
      'authProvider': authProvider,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      displayName: map['displayName'] as String? ?? 'User',
      email: map['email'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      phoneNumber: map['phoneNumber'] as String?,
      isGuest: (map['isGuest'] as int? ?? (map['isGuest'] == true ? 1 : 0)) == 1,
      authProvider: map['authProvider'] as String? ?? 'google',
    );
  }

  UserModel copyWith({
    String? id,
    String? displayName,
    String? email,
    String? photoUrl,
    String? phoneNumber,
    bool? isGuest,
    String? authProvider,
  }) {
    return UserModel(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isGuest: isGuest ?? this.isGuest,
      authProvider: authProvider ?? this.authProvider,
    );
  }
}
