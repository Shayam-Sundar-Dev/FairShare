import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/event_model.dart';
import '../../ui/providers/event_provider.dart';
import '../../ui/providers/expense_provider.dart';
import '../../ui/screens/events/event_detail_screen.dart';
import '../../ui/screens/events/widgets/join_trip_dialog.dart';

class DeepLinkHandler {
  static final DeepLinkHandler _instance = DeepLinkHandler._internal();
  factory DeepLinkHandler() => _instance;
  DeepLinkHandler._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _initialized = false;

  /// Global navigator key to perform navigation from deep links
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void init() {
    if (_initialized) return;
    _initialized = true;

    // Listen to incoming links while app is in foreground or background
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleUri(uri),
      onError: (err) => debugPrint('DeepLinkHandler stream error: $err'),
    );

    // Check if app was launched via a link
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleUri(uri);
      }
    }).catchError((err) {
      debugPrint('DeepLinkHandler getInitialLink error: $err');
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
    _initialized = false;
  }

  bool _isAppReady = false;
  String? _pendingCodeOrFileId;

  /// Call this when the app has transitioned out of the splash screen
  void markAppReady() {
    _isAppReady = true;
    if (_pendingCodeOrFileId != null) {
      final code = _pendingCodeOrFileId!;
      _pendingCodeOrFileId = null;
      _promptJoinTrip(code);
    }
  }

  void _handleUri(Uri uri) {
    debugPrint('DeepLinkHandler received URI: $uri');

    // Expected formats:
    // 1. https://drive.google.com/file/d/{fileId}/view?usp=sharing
    // 2. https://drive.google.com/open?id={fileId}
    // 3. fairshare://join?fileId={fileId}&code={code}
    // 4. fairshare://join/{codeOrFileId}
    // 5. fairshare://trip?fileId={fileId}

    String? codeOrFileId;

    if (uri.queryParameters.containsKey('fileId') && uri.queryParameters['fileId']!.isNotEmpty) {
      codeOrFileId = uri.queryParameters['fileId'];
    } else if (uri.queryParameters.containsKey('tripId') && uri.queryParameters['tripId']!.isNotEmpty) {
      codeOrFileId = uri.queryParameters['tripId'];
    } else if (uri.queryParameters.containsKey('code') && uri.queryParameters['code']!.isNotEmpty) {
      codeOrFileId = uri.queryParameters['code'];
    } else if (uri.host == 'drive.google.com' || uri.host == 'docs.google.com') {
      final foldersIndex = uri.pathSegments.indexOf('folders');
      final dIndex = uri.pathSegments.indexOf('d');
      if (foldersIndex != -1 && uri.pathSegments.length > foldersIndex + 1) {
        codeOrFileId = uri.pathSegments[foldersIndex + 1];
      } else if (dIndex != -1 && uri.pathSegments.length > dIndex + 1) {
        codeOrFileId = uri.pathSegments[dIndex + 1];
      } else if (uri.queryParameters.containsKey('id')) {
        codeOrFileId = uri.queryParameters['id'];
      }
    } else if (uri.scheme == 'fairshare') {
      if (uri.pathSegments.isNotEmpty) {
        codeOrFileId = uri.pathSegments.first;
      } else if (uri.host.isNotEmpty && uri.host != 'join' && uri.host != 'trip') {
        codeOrFileId = uri.host;
      }
    }

    if (codeOrFileId != null && codeOrFileId.isNotEmpty) {
      if (!_isAppReady) {
        debugPrint('DeepLinkHandler: App not ready yet, queuing $codeOrFileId');
        _pendingCodeOrFileId = codeOrFileId;
      } else {
        _promptJoinTrip(codeOrFileId);
      }
    }
  }

  Future<void> _promptJoinTrip(String codeOrFileId) async {
    debugPrint('DeepLinkHandler: _promptJoinTrip called for code/fileId: $codeOrFileId');

    // Wait until navigator is mounted (up to 20 attempts, 2 seconds)
    BuildContext? context;
    for (int i = 0; i < 20; i++) {
      context = navigatorKey.currentContext;
      if (context != null && context.mounted) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (context == null || !context.mounted) {
      debugPrint('DeepLinkHandler: navigator context not available after wait');
      return;
    }

    final navState = navigatorKey.currentState;
    if (navState == null) {
      debugPrint('DeepLinkHandler: navState is null');
      return;
    }

    try {
      final eventProvider = context.read<EventProvider>();
      final existing = eventProvider.events.where(
        (e) => (e.shareCode != null && e.shareCode!.toUpperCase() == codeOrFileId.toUpperCase()) ||
               (e.driveFileId != null && e.driveFileId == codeOrFileId),
      ).firstOrNull;

      if (existing != null) {
        debugPrint('DeepLinkHandler: Trip already joined: ${existing.title} (${existing.id})');
        final expenseProvider = context.read<ExpenseProvider>();
        await eventProvider.selectEvent(existing.id);
        await expenseProvider.loadForEvent(existing.id);
        await eventProvider.computeFinancials(existing.id);
        if (context.mounted) {
          navState.push(
            MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: existing.id)),
          );
        }
        return;
      }

      debugPrint('DeepLinkHandler: Opening JoinTripDialog for $codeOrFileId');
      if (context.mounted) {
        final joined = await showDialog<EventModel?>(
          context: context,
          useRootNavigator: true,
          builder: (_) => JoinTripDialog(initialCode: codeOrFileId),
        );

        if (joined != null && context.mounted) {
          final expenseProvider = context.read<ExpenseProvider>();
          await eventProvider.selectEvent(joined.id);
          await expenseProvider.loadForEvent(joined.id);
          await eventProvider.computeFinancials(joined.id);
          if (context.mounted) {
            navState.push(
              MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: joined.id)),
            );
          }
        }
      }
    } catch (e, stack) {
      debugPrint('DeepLinkHandler error showing join dialog: $e\n$stack');
    }
  }

  /// Builds a deep link URL for joining a trip
  static String buildJoinUrl({required String shareCode, String? driveFileId}) {
    if (driveFileId != null && driveFileId.isNotEmpty) {
      return 'fairshare://join?fileId=$driveFileId';
    }
    return 'fairshare://join?code=$shareCode';
  }

  /// Generates a clickable HTTPS short link that redirects to fairshare://join?fileId=...
  /// This ensures messaging apps like WhatsApp render the link as a clickable hyperlink.
  static Future<String> createClickableJoinUrl({
    required String shareCode,
    String? driveFileId,
  }) async {
    final deepLink = buildJoinUrl(shareCode: shareCode, driveFileId: driveFileId);
    try {
      final uri = Uri.parse(
        'https://tinyurl.com/api-create.php?url=${Uri.encodeComponent(deepLink)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200 && response.body.trim().startsWith('http')) {
        return response.body.trim();
      }
    } catch (e) {
      debugPrint('DeepLinkHandler: Failed to create short clickable link: $e');
    }
    return deepLink;
  }
}
