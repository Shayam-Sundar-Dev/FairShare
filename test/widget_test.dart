import 'package:flutter_test/flutter_test.dart';
import 'package:fairshare/core/services/deep_link_handler.dart';
import 'package:fairshare/core/utils/phone_helper.dart';
import 'package:fairshare/core/utils/upi_payment_helper.dart';
import 'package:fairshare/data/services/google_drive_trip_sync_service.dart';

void main() {
  group('DeepLinkHandler URL tests', () {
    test('buildJoinUrl formats correctly with driveFileId', () {
      final url = DeepLinkHandler.buildJoinUrl(
        shareCode: 'TEST12',
        driveFileId: '14oPsyavWRzD5wmkT7XCoR5_v95N4_37w',
      );
      expect(url, 'fairshare://join?fileId=14oPsyavWRzD5wmkT7XCoR5_v95N4_37w');
    });

    test('buildJoinUrl formats correctly without driveFileId', () {
      final url = DeepLinkHandler.buildJoinUrl(
        shareCode: 'ABC123',
        driveFileId: null,
      );
      expect(url, 'fairshare://join?code=ABC123');
    });
  });

  group('GoogleDriveTripSyncService ID Extraction', () {
    const fileId = '14oPsyavWRzD5wmkT7XCoR5_v95N4_37w';

    test('extracts driveFileId from shared folder link', () {
      final link = 'https://drive.google.com/drive/folders/$fileId?usp=sharing';
      expect(GoogleDriveTripSyncService.extractDriveFileId(link), fileId);
    });

    test('extracts driveFileId from standard file link', () {
      final link = 'https://drive.google.com/file/d/$fileId/view';
      expect(GoogleDriveTripSyncService.extractDriveFileId(link), fileId);
    });

    test('extracts driveFileId from raw ID string', () {
      expect(GoogleDriveTripSyncService.extractDriveFileId(fileId), fileId);
    });
  });

  group('PhoneHelper utility tests', () {
    test('cleans and normalizes phone numbers to last 10 digits', () {
      expect(PhoneHelper.clean('+91 98765 43210'), '919876543210');
      expect(PhoneHelper.last10('+91 98765 43210'), '9876543210');
      expect(PhoneHelper.clean('098765-43210'), '09876543210');
      expect(PhoneHelper.last10('098765-43210'), '9876543210');
    });

    test('accurately matches same phones across different prefixes', () {
      expect(PhoneHelper.isSamePhone('+919876543210', '9876543210'), isTrue);
      expect(PhoneHelper.isSamePhone('09876543210', '+91 98765 43210'), isTrue);
      expect(PhoneHelper.isSamePhone('9876543210', '1234567890'), isFalse);
    });

    test('extracts phone from phone-based UPI IDs', () {
      expect(PhoneHelper.extractPhoneFromUpi('9876543210@okicici'), '9876543210');
      expect(PhoneHelper.extractPhoneFromUpi('9876543210@paytm'), '9876543210');
      expect(PhoneHelper.extractPhoneFromUpi('john.doe@okaxis'), '');
    });
  });

  group('UpiPaymentHelper URI builders', () {
    test('builds valid upi://pay URI', () {
      final uri = UpiPaymentHelper.buildUpiUri(
        upiId: 'user@okaxis',
        payeeName: 'John Doe',
        amount: 250.50,
        note: 'Lunch share',
      );

      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(uri.queryParameters['pa'], 'user@okaxis');
      expect(uri.queryParameters['pn'], 'John Doe');
      expect(uri.queryParameters['am'], '250.50');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['tn'], 'Lunch share');
    });

    test('builds valid tez://upi/pay URI', () {
      final uri = UpiPaymentHelper.buildGPayUri(
        upiId: 'user@okaxis',
        payeeName: 'John Doe',
        amount: 100.0,
      );

      expect(uri.scheme, 'tez');
      expect(uri.host, 'upi');
      expect(uri.path, '/pay');
      expect(uri.queryParameters['pa'], 'user@okaxis');
      expect(uri.queryParameters['am'], '100.00');
    });
  });
}
