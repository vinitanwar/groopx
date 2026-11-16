import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../auth/data/auth_api.dart';
import 'notification_payload.dart';

@pragma('vm:entry-point')
void notificationReplyBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await LocalNotifications.initialize();
  await LocalNotifications.reply(response);
}

class LocalNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initialization;
  static FutureOr<void> Function(Map<String, dynamic>)? _onOpen;
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get ready => _ready;
  static bool _ready = false;

  static Future<void> initialize({
    FutureOr<void> Function(Map<String, dynamic>)? onOpen,
  }) async {
    if (!supported) return;
    if (onOpen != null) _onOpen = onOpen;
    try {
      await (_initialization ??= _initialize());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  static Future<void> _initialize() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) async {
        if (response.actionId == 'reply') {
          await reply(response);
          return;
        }
        final data = _decode(response.payload);
        if (data == null) return;
        if (data.containsKey('recipient_id') &&
            !notificationMatchesAccount(
              data,
              await AuthSession.instance.accessToken,
            ))
          return;
        await _onOpen?.call(data);
      },
      onDidReceiveBackgroundNotificationResponse: notificationReplyBackground,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'groopx_messages',
            'Messages',
            description: 'New GroopX messages and shared media',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
    _ready = true;
  }

  static Future<void> openInitial() async {
    if (!supported || !_ready) return;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp != true || response == null) return;
    if (response.actionId == 'reply') {
      await reply(response);
      return;
    }
    final data = _decode(response.payload);
    if (data == null) return;
    if (data.containsKey('recipient_id') &&
        !notificationMatchesAccount(
          data,
          await AuthSession.instance.accessToken,
        ))
      return;
    await _onOpen?.call(data);
  }

  static Map<String, dynamic>? _decode(String? payload) {
    try {
      return jsonDecode(payload ?? '') as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> show(
    String title,
    String body,
    Map<String, dynamic> data, {
    bool failed = false,
  }) async {
    if (!supported) return;
    await initialize();
    final kind = data['type']?.toString();
    final chat = kind == 'message' || kind == 'mention';
    // Reject stale pushes after logout or an account switch.
    if (data.containsKey('recipient_id') &&
        !notificationMatchesAccount(
          data,
          await AuthSession.instance.accessToken,
        ))
      return;
    final canReply =
        chat &&
        data['notification_reply'] == '1' &&
        data['conversation_id']?.toString().isNotEmpty == true &&
        data['message_id']?.toString().isNotEmpty == true;
    final channel = kind == 'call'
        ? 'groopx_calls'
        : kind == 'reminder'
        ? 'groopx_reminders'
        : chat
        ? 'groopx_messages'
        : 'groopx_updates';
    await _plugin.show(
      notificationId(data),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          chat
              ? 'Messages'
              : kind == 'call'
              ? 'Calls'
              : kind == 'reminder'
              ? 'Reminders'
              : 'Updates',
          icon: 'ic_notification',
          importance: Importance.high,
          priority: Priority.high,
          playSound: !failed,
          enableVibration: !failed,
          visibility: NotificationVisibility.private,
          styleInformation: BigTextStyleInformation(body),
          actions: canReply
              ? const [
                  AndroidNotificationAction(
                    'reply',
                    'Reply',
                    inputs: [
                      AndroidNotificationActionInput(label: 'Type a reply'),
                    ],
                    showsUserInterface: false,
                    cancelNotification: false,
                  ),
                ]
              : null,
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  static Future<void> reply(NotificationResponse response) async {
    if (response.actionId != 'reply') return;
    final data = _decode(response.payload);
    final text = response.input?.trim() ?? '';
    if (data == null || text.isEmpty) return;
    final conversation = data['conversation_id']?.toString() ?? '';
    final message = data['message_id']?.toString() ?? '';
    if (conversation.isEmpty ||
        message.isEmpty ||
        data['notification_reply'] != '1')
      return;
    var token = await AuthSession.instance.accessToken;
    if (!notificationMatchesAccount(data, token)) {
      await _plugin.cancel(response.id ?? notificationId(data));
      return;
    }
    final client = Dio(
      BaseOptions(
        baseUrl: const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://10.0.2.2:8080/api/v1',
        ),
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
      ),
    );
    final payload = {
      'text': text,
      'client_message_id': notificationReplyKey(conversation, message, text),
    };
    try {
      try {
        await client.post(
          '/conversations/${Uri.encodeComponent(conversation)}/messages',
          data: payload,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      } on DioException catch (error) {
        if (error.response?.statusCode != 401) rethrow;
        // Refresh through the existing auth flow, then bind retry to the same account.
        await AuthApi.instance.refresh();
        token = await AuthSession.instance.accessToken;
        if (!notificationMatchesAccount(data, token)) return;
        await client.post(
          '/conversations/${Uri.encodeComponent(conversation)}/messages',
          data: payload,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      }
      // Each message has its own ID, so this cannot erase a newer incoming message.
      await _plugin.cancel(response.id ?? notificationId(data));
    } catch (_) {
      await show(
        'Reply not sent',
        'Open this chat to check or retry your reply: ${text.length > 300 ? text.substring(0, 300) : text}',
        data,
        failed: true,
      );
    } finally {
      client.close();
    }
  }

  static Future<void> clear() async {
    if (supported && _ready) await _plugin.cancelAll();
  }
}
