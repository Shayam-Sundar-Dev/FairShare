import 'package:flutter_test/flutter_test.dart';
import 'package:fairshare/data/models/user_model.dart';

void main() {
  group('UserModel Tests', () {
    test('toMap and fromMap work correctly for Google user', () {
      final user = UserModel(
        id: 'google_12345',
        displayName: 'John Doe',
        email: 'john@example.com',
        photoUrl: 'https://example.com/photo.jpg',
        isGuest: false,
        authProvider: 'google',
      );

      final map = user.toMap();
      expect(map['id'], 'google_12345');
      expect(map['displayName'], 'John Doe');
      expect(map['email'], 'john@example.com');
      expect(map['photoUrl'], 'https://example.com/photo.jpg');
      expect(map['isGuest'], 0);
      expect(map['authProvider'], 'google');

      final reconstructed = UserModel.fromMap(map);
      expect(reconstructed.id, user.id);
      expect(reconstructed.displayName, user.displayName);
      expect(reconstructed.email, user.email);
      expect(reconstructed.photoUrl, user.photoUrl);
      expect(reconstructed.isGuest, isFalse);
      expect(reconstructed.authProvider, 'google');
    });

    test('toMap and fromMap work correctly for Guest user', () {
      final user = UserModel(
        id: 'guest_999',
        displayName: 'Guest User',
        email: '',
        isGuest: true,
        authProvider: 'guest',
      );

      final map = user.toMap();
      expect(map['isGuest'], 1);
      expect(map['authProvider'], 'guest');

      final reconstructed = UserModel.fromMap(map);
      expect(reconstructed.id, user.id);
      expect(reconstructed.isGuest, isTrue);
      expect(reconstructed.authProvider, 'guest');
    });

    test('copyWith updates properties properly', () {
      const user = UserModel(
        id: 'user_1',
        displayName: 'User One',
        email: 'user1@example.com',
        isGuest: false,
      );

      final updated = user.copyWith(displayName: 'Updated Name');
      expect(updated.displayName, 'Updated Name');
      expect(updated.email, 'user1@example.com');
      expect(updated.id, 'user_1');
    });

    test('isDemo identifies demo accounts properly', () {
      const demoUser1 = UserModel(
        id: 'demo_123',
        displayName: 'Demo',
        email: 'demo@fairshare.app',
        authProvider: 'demo',
      );
      expect(demoUser1.isDemo, isTrue);

      const demoUser2 = UserModel(
        id: 'google_user_999',
        displayName: 'Demo Google',
        email: 'user@gmail.com',
        authProvider: 'google',
      );
      expect(demoUser2.isDemo, isTrue);

      const realGoogleUser = UserModel(
        id: 'real_google_123',
        displayName: 'Real User',
        email: 'real.user@gmail.com',
        authProvider: 'google',
      );
      expect(realGoogleUser.isDemo, isFalse);
    });
  });
}
