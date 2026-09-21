import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_api.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try { await Firebase.initializeApp(); } catch (_) {}
}

class PushService {
  PushService._();
  static StreamSubscription<String>? _refreshSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static bool _initialized = false;

  static Future<void> initialize({required void Function(Map<String, dynamic>) onOpen, required void Function(String, String) onForeground}) async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      _refreshSubscription = messaging.onTokenRefresh.listen((newToken) async {
        try { await NotificationApi.instance.registerDevice(newToken, _platform); } catch (_) {}
      });
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
        onForeground(message.notification?.title ?? 'GroopX', message.notification?.body ?? 'You have a new update');
      });
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) => onOpen(message.data));
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpen(initial.data);
      _initialized = true;
      await registerCurrentDevice();
    } catch (_) {
      // Firebase platform files may not be configured in local development.
    }
  }

  static Future<void> registerCurrentDevice() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await NotificationApi.instance.registerDevice(token, _platform);
    } catch (_) {}
  }

  static Future<void> dispose() async { await _refreshSubscription?.cancel(); await _foregroundSubscription?.cancel(); await _openedSubscription?.cancel(); _refreshSubscription = null; _foregroundSubscription = null; _openedSubscription = null; _initialized = false; }

  static String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}
