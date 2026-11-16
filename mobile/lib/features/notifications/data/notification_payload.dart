import 'dart:convert';
import 'package:crypto/crypto.dart';

String? notificationUserId(String? token) {
  try {
    if (token == null) return null;
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    );
    return claims['sub'] as String?;
  } catch (_) {
    return null;
  }
}

bool notificationMatchesAccount(Map<String, dynamic> data, String? token) {
  final recipient = data['recipient_id']?.toString();
  return recipient != null &&
      recipient.isNotEmpty &&
      recipient == notificationUserId(token);
}

// Stable across isolates and process restarts. Also used for idempotent HTTP retries.
String notificationReplyKey(String conversation, String message, String text) =>
    'notification-${sha256.convert(utf8.encode(jsonEncode([conversation, message, text]))).toString()}';

int notificationId(Map<String, dynamic> data) {
  final key =
      data['message_id'] ??
      data['call_id'] ??
      data['reminder_id'] ??
      data['conversation_id'] ??
      jsonEncode(data);
  final digest = sha256.convert(utf8.encode(key.toString())).bytes;
  return ((digest[0] << 24) |
          (digest[1] << 16) |
          (digest[2] << 8) |
          digest[3]) &
      0x7fffffff;
}
