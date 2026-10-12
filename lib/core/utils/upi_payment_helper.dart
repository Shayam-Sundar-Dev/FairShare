import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'currency_formatter.dart';

class UpiPaymentResult {
  final bool isSuccess;
  final String status; // "SUCCESS", "FAILURE", "CANCELLED", "UNKNOWN", "LAUNCHED"
  final String? rawResponse;
  final Map<String, dynamic>? params;

  const UpiPaymentResult({
    required this.isSuccess,
    required this.status,
    this.rawResponse,
    this.params,
  });
}

class UpiPaymentHelper {
  static const MethodChannel _channel = MethodChannel('com.fairshare.fairshare/upi');

  /// Starts a UPI payment session and waits for Google Pay's native callback result
  static Future<UpiPaymentResult> startUpiPayment({
    required String upiId,
    required String payeeName,
    required double amount,
    String note = '',
    String? packageName = 'com.google.android.apps.nbu.paisa.user',
  }) async {
    final cleanUpi = upiId.trim();
    final cleanName = payeeName.trim();
    final cleanNote = note.trim();

    final standardUpiUri = buildUpiUri(
      upiId: cleanUpi,
      payeeName: cleanName,
      amount: amount,
      note: cleanNote,
    );

    try {
      final res = await _channel.invokeMethod<Map>('launchUpiPayment', {
        'uri': standardUpiUri.toString(),
        'package': packageName,
      });

      if (res != null) {
        final isSuccess = res['isSuccess'] == true;
        final status = (res['status'] as String?) ?? (isSuccess ? 'SUCCESS' : 'UNKNOWN');
        return UpiPaymentResult(
          isSuccess: isSuccess,
          status: status,
          rawResponse: res['rawResponse'] as String?,
          params: (res['params'] as Map?)?.cast<String, dynamic>(),
        );
      }
    } on MissingPluginException catch (_) {
      // Fallback if channel is missing
    } catch (e) {
      if (packageName != null) {
        try {
          final res = await _channel.invokeMethod<Map>('launchUpiPayment', {
            'uri': standardUpiUri.toString(),
            'package': null,
          });
          if (res != null) {
            final isSuccess = res['isSuccess'] == true;
            final status = (res['status'] as String?) ?? (isSuccess ? 'SUCCESS' : 'UNKNOWN');
            return UpiPaymentResult(
              isSuccess: isSuccess,
              status: status,
              rawResponse: res['rawResponse'] as String?,
              params: (res['params'] as Map?)?.cast<String, dynamic>(),
            );
          }
        } catch (_) {}
      }
    }

    // Fallback: use url_launcher
    final launched = await launchGooglePay(
      upiId: cleanUpi,
      payeeName: cleanName,
      amount: amount,
      note: cleanNote,
    );

    return UpiPaymentResult(
      isSuccess: false,
      status: launched ? 'LAUNCHED' : 'FAILED',
    );
  }
  /// Builds standard UPI payment URI
  static Uri buildUpiUri({
    required String upiId,
    required String payeeName,
    required double amount,
    String note = '',
    String currency = 'INR',
  }) {
    final queryParams = {
      'pa': upiId.trim(),
      'pn': payeeName.trim(),
      'am': amount.toStringAsFixed(2),
      'cu': currency,
      if (note.isNotEmpty) 'tn': note,
    };

    return Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: queryParams,
    );
  }

  /// Builds Google Pay specific intent URI (tez://upi/pay)
  static Uri buildGPayUri({
    required String upiId,
    required String payeeName,
    required double amount,
    String note = '',
    String currency = 'INR',
  }) {
    final queryParams = {
      'pa': upiId.trim(),
      'pn': payeeName.trim(),
      'am': amount.toStringAsFixed(2),
      'cu': currency,
      if (note.isNotEmpty) 'tn': note,
    };

    return Uri(
      scheme: 'tez',
      host: 'upi',
      path: 'pay',
      queryParameters: queryParams,
    );
  }

  /// Launches Google Pay directly or falls back to any available UPI app
  static Future<bool> launchGooglePay({
    required String upiId,
    required String payeeName,
    required double amount,
    String note = '',
  }) async {
    final cleanUpi = upiId.trim();
    final cleanName = payeeName.trim();
    final cleanAmount = amount.toStringAsFixed(2);
    final cleanNote = note.trim();

    // 1. Target Google Pay package explicitly using standard UPI Intent
    // (This avoids launching the QR scanner mode that causes "Cannot pay with this QR code")
    final gpayIntent = Uri.parse(
      'intent://pay?pa=${Uri.encodeComponent(cleanUpi)}&pn=${Uri.encodeComponent(cleanName)}&am=$cleanAmount&cu=INR${cleanNote.isNotEmpty ? "&tn=${Uri.encodeComponent(cleanNote)}" : ""}#Intent;scheme=upi;package=com.google.android.apps.nbu.paisa.user;end',
    );
    try {
      final ok = await launchUrl(gpayIntent, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    // 2. Standard upi://pay intent (opens Google Pay or system UPI chooser without QR code mode)
    final standardUpiUri = buildUpiUri(
      upiId: cleanUpi,
      payeeName: cleanName,
      amount: amount,
      note: cleanNote,
    );
    try {
      if (await canLaunchUrl(standardUpiUri)) {
        final ok = await launchUrl(standardUpiUri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (_) {}

    // 3. Fallback to tez:// scheme if standard intent is not supported
    final gpayUri = buildGPayUri(
      upiId: cleanUpi,
      payeeName: cleanName,
      amount: amount,
      note: cleanNote,
    );
    try {
      if (await canLaunchUrl(gpayUri)) {
        return await launchUrl(gpayUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    return false;
  }

  /// Opens Google Pay directly to send a payment request to the debtor
  static Future<bool> launchGooglePayForRequest({
    required String creditorUpiId,
    required String creditorName,
    required double amount,
    required String debtorName,
    String? debtorPhone,
    String? debtorUpiId,
    String note = '',
  }) async {
    final queryParams = {
      'pa': creditorUpiId.trim(),
      'pn': creditorName.trim(),
      'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      if (note.isNotEmpty) 'tn': note,
    };

    // 1. Try tez://upi/collect
    final collectUri = Uri(
      scheme: 'tez',
      host: 'upi',
      path: 'collect',
      queryParameters: queryParams,
    );
    try {
      if (await canLaunchUrl(collectUri)) {
        final ok = await launchUrl(collectUri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (_) {}

    // 2. Try tez://upi/request
    final requestUri = Uri(
      scheme: 'tez',
      host: 'upi',
      path: 'request',
      queryParameters: queryParams,
    );
    try {
      if (await canLaunchUrl(requestUri)) {
        final ok = await launchUrl(requestUri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (_) {}

    // 3. Try tez:// scheme directly
    final tezBaseUri = Uri.parse('tez://');
    try {
      if (await canLaunchUrl(tezBaseUri)) {
        final ok = await launchUrl(tezBaseUri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (_) {}

    // 4. Try Android package intent via intent: scheme
    final gpayIntent = Uri.parse(
      'intent:#Intent;package=com.google.android.apps.nbu.paisa.user;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;end',
    );
    try {
      final ok = await launchUrl(gpayIntent, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    // 5. Try android-app scheme
    final gpayAppUri = Uri.parse('android-app://com.google.android.apps.nbu.paisa.user');
    try {
      if (await canLaunchUrl(gpayAppUri)) {
        final ok = await launchUrl(gpayAppUri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (_) {}

    return false;
  }

  /// Shares a pre-formatted Group Installment Request message
  static void shareInstallmentRequest({
    required String tripTitle,
    required int installmentNumber,
    required double amount,
    required String hostName,
    required String hostUpiId,
    String currency = '₹',
    List<String> memberNames = const [],
  }) {
    final upiUri = buildUpiUri(
      upiId: hostUpiId,
      payeeName: hostName,
      amount: amount,
      note: '$tripTitle Installment #$installmentNumber',
    );

    final buffer = StringBuffer();
    buffer.writeln('✈️ *FairShare Trip Installment Request: $tripTitle*');
    buffer.writeln('----------------------------------------');
    buffer.writeln('📌 *Milestone:* Installment #$installmentNumber');
    buffer.writeln('💰 *Amount per Person:* ${CurrencyFormatter.format(amount, symbol: currency)}');
    buffer.writeln('👤 *Host (Pay to):* $hostName');
    buffer.writeln('🏦 *Host UPI ID:* `$hostUpiId`');
    if (memberNames.isNotEmpty) {
      buffer.writeln('👥 *Members Due:* ${memberNames.join(", ")}');
    }
    buffer.writeln('----------------------------------------');
    buffer.writeln('👉 *Tap link to pay via Google Pay / UPI:*');
    buffer.writeln(upiUri.toString());
    buffer.writeln('\n_Once paid, it will be added to the Trip Committee Pool!_');

    SharePlus.instance.share(ShareParams(
      text: buffer.toString(),
      subject: 'Trip Installment #$installmentNumber - $tripTitle',
    ));
  }

  /// Shares a pre-formatted Settlement Request message (Sent by Creditor to Debtor)
  static void shareSettlementRequest({
    required String tripTitle,
    required String debtorName,
    required String creditorName,
    required double amount,
    required String creditorUpiId,
    String currency = '₹',
  }) {
    final upiUri = buildUpiUri(
      upiId: creditorUpiId,
      payeeName: creditorName,
      amount: amount,
      note: 'Settlement for $tripTitle',
    );

    final buffer = StringBuffer();
    buffer.writeln('🤝 *FairShare Settlement Request*');
    buffer.writeln('----------------------------------------');
    buffer.writeln('Trip: *$tripTitle*');
    buffer.writeln('Hi $debtorName, please settle your balance of ${CurrencyFormatter.format(amount, symbol: currency)} with $creditorName:');
    buffer.writeln('🏦 *Payee UPI ID:* `$creditorUpiId`');
    buffer.writeln('----------------------------------------');
    buffer.writeln('👉 *Tap link to pay via Google Pay / UPI:*');
    buffer.writeln(upiUri.toString());
    buffer.writeln('\n_Generated via FairShare_');

    SharePlus.instance.share(ShareParams(
      text: buffer.toString(),
      subject: 'Settlement Request: $tripTitle',
    ));
  }

  /// Shares a pre-formatted Settlement Payment Note (Sent by Debtor to Creditor/Receiver)
  static void shareDebtorSettlementNotice({
    required String tripTitle,
    required String debtorName,
    required String creditorName,
    required double amount,
    required String creditorUpiId,
    String currency = '₹',
  }) {
    final upiUri = buildUpiUri(
      upiId: creditorUpiId,
      payeeName: creditorName,
      amount: amount,
      note: 'Settlement for $tripTitle',
    );

    final buffer = StringBuffer();
    buffer.writeln('💳 *FairShare Settlement Payment*');
    buffer.writeln('----------------------------------------');
    buffer.writeln('Trip: *$tripTitle*');
    buffer.writeln('Hi $creditorName, I am settling my balance of ${CurrencyFormatter.format(amount, symbol: currency)}.');
    buffer.writeln('🏦 *Paying to UPI ID:* `$creditorUpiId`');
    buffer.writeln('----------------------------------------');
    buffer.writeln('👉 *UPI Payment Link:*');
    buffer.writeln(upiUri.toString());
    buffer.writeln('\n_Please verify and confirm once received in your account!_');

    SharePlus.instance.share(ShareParams(
      text: buffer.toString(),
      subject: 'Settlement Payment: $tripTitle',
    ));
  }

  /// Copies UPI link to clipboard
  static Future<void> copyUpiLinkToClipboard(BuildContext context, Uri uri) async {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('UPI Payment Link copied to clipboard!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
