import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../auth/data/auth_api.dart';
import 'local_notifications.dart';
import 'notification_api.dart';
import 'notification_payload.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    // OS notification payloads already display themselves. Only render upgraded
    // Android data messages here, preventing duplicate alerts.
    if (message.notification == null &&
        message.data['notification_reply'] == '1') {
      await LocalNotifications.show(
        message.data['title']?.toString() ?? 'GroopX',
        message.data['body']?.toString() ?? 'New message',
        message.data,
      );
    }
  } catch (_) {
    debugPrint('GroopX background notification could not be displayed.');
  }
}

class PushService {
  PushService._();
  static StreamSubscription<String>? _refreshSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static Timer? _retry;
  static int _attempts = 0;
  static bool _initialized = false;
  static Future<void>? _initializing;

  static Future<void> initialize({
    required FutureOr<void> Function(Map<String, dynamic>) onOpen,
    required void Function(String, String, Map<String, dynamic>) onForeground,
  }) async {
    if (_initialized) return;
    await (_initializing ??= _initialize(onOpen, onForeground));
    _initializing = null;
  }

  static Future<void> _initialize(
    FutureOr<void> Function(Map<String, dynamic>) onOpen,
    void Function(String, String, Map<String, dynamic>) onForeground,
  ) async {
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // iOS keeps its native FCM rendering; Android uses local actionable alerts.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      try {
        await LocalNotifications.initialize(onOpen: onOpen);
      } catch (_) {
        debugPrint(
          'Local notifications unavailable; using legacy push registration.',
        );
      }
      _refreshSubscription = messaging.onTokenRefresh.listen((_) {
        unawaited(registerCurrentDevice());
      });
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((
        message,
      ) async {
        if (message.data.containsKey('recipient_id') &&
            !notificationMatchesAccount(
              message.data,
              await AuthSession.instance.accessToken,
            ))
          return;
        final title =
            message.notification?.title ??
            message.data['title']?.toString() ??
            'GroopX';
        final body =
            message.notification?.body ??
            message.data['body']?.toString() ??
            'You have a new update';
        try {
          await LocalNotifications.show(title, body, message.data);
        } catch (_) {
          debugPrint('Foreground notification could not be displayed.');
        }
        onForeground(title, body, message.data);
      });
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
        message,
      ) {
        unawaited(Future<void>.sync(() => onOpen(message.data)));
      });
      _initialized = true;
      final initial = await messaging.getInitialMessage();
      if (initial != null) await onOpen(initial.data);
      await LocalNotifications.openInitial();
      await registerCurrentDevice();
    } catch (_) {
      debugPrint(
        'Push initialization incomplete; check Firebase configuration.',
      );
    }
  }

  static Future<void> registerCurrentDevice() async {
    _retry?.cancel();
    if ((await AuthSession.instance.accessToken)?.isNotEmpty != true) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) throw StateError('FCM token not ready');
      await NotificationApi.instance.registerDevice(
        token,
        _platform,
        notificationReply:
            LocalNotifications.supported && LocalNotifications.ready,
      );
      _attempts = 0;
    } catch (_) {
      if (_attempts++ < 5)
        _retry = Timer(
          Duration(seconds: 5 * _attempts),
          () => unawaited(registerCurrentDevice()),
        );
    }
  }

  static Future<void> unregisterCurrentDevice() async {
    _retry?.cancel();
    _attempts = 0;
    await LocalNotifications.clear();
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await NotificationApi.instance.unregisterDevice(token);
    } catch (_) {}
  }

  static Future<void> dispose() async {
    _retry?.cancel();
    await _refreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    _refreshSubscription = null;
    _foregroundSubscription = null;
    _openedSubscription = null;
    _initialized = false;
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}
