import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:groopx/features/notifications/data/notification_payload.dart';

void main() {
  String token(String id) =>
      'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': id})))}.signature';
  test(
    'stale notification cannot target another account or logged-out session',
    () {
      final data = {'recipient_id': 'alice'};
      expect(notificationMatchesAccount(data, token('alice')), isTrue);
      expect(notificationMatchesAccount(data, token('bob')), isFalse);
      expect(notificationMatchesAccount(data, null), isFalse);
      expect(notificationMatchesAccount({}, token('alice')), isFalse);
      expect(notificationMatchesAccount(data, 'malformed'), isFalse);
    },
  );
  test(
    'reply retries deduplicate but different text or conversations do not',
    () {
      final key = notificationReplyKey('chat', 'message', 'Hello');
      expect(key.length, lessThanOrEqualTo(80));
      expect(notificationReplyKey('chat', 'message', 'Hello'), key);
      expect(notificationReplyKey('chat', 'message', 'Changed'), isNot(key));
      expect(notificationReplyKey('other', 'message', 'Hello'), isNot(key));
    },
  );
  test('reply completion cancels only the original message notification', () {
    expect(
      notificationId({'message_id': 'first'}),
      notificationId({'message_id': 'first'}),
    );
    expect(
      notificationId({'message_id': 'first'}),
      isNot(notificationId({'message_id': 'second'})),
    );
  });
}
