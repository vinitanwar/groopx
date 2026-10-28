import 'package:dio/dio.dart';

import '../../auth/data/auth_api.dart';

class ReminderItem {
  const ReminderItem({required this.id, required this.title, required this.scheduledAt, required this.status, this.notes = '', this.conversationId = '', this.conversationTitle = '', this.itemType = 'reminder', this.callKind = '', this.repeatRule = 'none', this.isOrganizer = true, this.inviteStatus = 'organizer', this.organizerName = '', this.invitedCount = 0, this.acceptedCount = 0, this.pendingCount = 0, this.declinedCount = 0});
  factory ReminderItem.fromJson(Map<String, dynamic> json) {
    final isOrganizer = json['is_organizer'] as bool? ?? true;
    return ReminderItem(
      id: json['id'] as String,
      title: json['title'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String).toLocal(),
      status: json['status'] as String? ?? 'upcoming',
      notes: json['notes'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      conversationTitle: json['conversation_title'] as String? ?? '',
      itemType: json['item_type'] as String? ?? 'reminder',
      callKind: json['call_kind'] as String? ?? '',
      repeatRule: json['repeat_rule'] as String? ?? 'none',
      isOrganizer: isOrganizer,
      inviteStatus: json['invite_status'] as String? ?? (isOrganizer ? 'organizer' : 'pending'),
      organizerName: json['organizer_name'] as String? ?? '',
      invitedCount: json['invited_count'] as int? ?? 0,
      acceptedCount: json['accepted_count'] as int? ?? 0,
      pendingCount: json['pending_count'] as int? ?? 0,
      declinedCount: json['declined_count'] as int? ?? 0,
    );
  }
  final String id, title, status, notes, conversationId, conversationTitle, itemType, callKind, repeatRule, inviteStatus, organizerName;
  final bool isOrganizer;
  final int invitedCount, acceptedCount, pendingCount, declinedCount;
  final DateTime scheduledAt;
  bool get meeting => itemType == 'meeting';
  bool get invited => meeting && !isOrganizer;
  String get repeatLabel => switch (repeatRule) {
    'daily' => 'Every day',
    'weekly' => 'Every week',
    'monthly' => 'Every month',
    _ => '',
  };
}

class MeetingAttendee {
  const MeetingAttendee({required this.userId, required this.name, required this.response, this.username = '', this.avatarUrl = '', this.respondedAt});
  factory MeetingAttendee.fromJson(Map<String, dynamic> json) => MeetingAttendee(
    userId: json['user_id'] as String,
    name: json['name'] as String? ?? 'GroopX member',
    username: json['username'] as String? ?? '',
    avatarUrl: json['avatar_url'] as String? ?? '',
    response: json['response'] as String? ?? 'pending',
    respondedAt: json['responded_at'] == null ? null : DateTime.parse(json['responded_at'] as String).toLocal(),
  );
  final String userId, name, username, avatarUrl, response;
  final DateTime? respondedAt;
}

class ReminderApi {
  ReminderApi._() {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await AuthSession.instance.accessToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }, onError: (error, handler) async {
      if (error.response?.statusCode == 401 && error.requestOptions.extra['retried'] != true) {
        try {
          await AuthApi.instance.refresh();
          error.requestOptions.headers['Authorization'] = 'Bearer ${await AuthSession.instance.accessToken}';
          error.requestOptions.extra['retried'] = true;
          return handler.resolve(await _dio.fetch(error.requestOptions));
        } catch (_) {}
      }
      handler.next(error);
    }));
  }
  static final instance = ReminderApi._();
  final Dio _dio = Dio(BaseOptions(baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api/v1'), connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10)));

  Future<List<ReminderItem>> list(String status, {String itemType = ''}) async {
    final response = await _dio.get<Map<String, dynamic>>('/reminders', queryParameters: {'status': status, if (itemType.isNotEmpty) 'item_type': itemType});
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => ReminderItem.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<void> create({required String title, required DateTime scheduledAt, String notes = '', String conversationId = '', String itemType = 'reminder', String callKind = '', String repeatRule = 'none', bool inviteParticipants = false}) async {
    await _dio.post('/reminders', data: {'title': title, 'scheduled_at': scheduledAt.toUtc().toIso8601String(), 'notes': notes, 'conversation_id': conversationId, 'item_type': itemType, 'call_kind': callKind, 'repeat_rule': repeatRule, 'invite_participants': inviteParticipants, if (repeatRule == 'monthly') 'repeat_anchor_day': scheduledAt.day});
  }
  Future<void> updateStatus(String id, String status) => _dio.patch('/reminders/$id', data: {'status': status});
  Future<void> snooze(String id, DateTime scheduledAt) => _dio.patch('/reminders/$id', data: {'scheduled_at': scheduledAt.toUtc().toIso8601String(), 'status': 'upcoming'});
  Future<void> update(String id, {required String title, required DateTime scheduledAt, String notes = '', String conversationId = '', String itemType = 'reminder', String callKind = '', String repeatRule = 'none', bool inviteParticipants = false}) => _dio.patch('/reminders/$id', data: {'title': title, 'scheduled_at': scheduledAt.toUtc().toIso8601String(), 'notes': notes, 'status': 'upcoming', 'conversation_id': conversationId, 'item_type': itemType, 'call_kind': callKind, 'repeat_rule': repeatRule, 'invite_participants': inviteParticipants, if (repeatRule == 'monthly') 'repeat_anchor_day': scheduledAt.day});
  Future<void> respond(String id, String response) => _dio.patch('/reminders/$id/respond', data: {'response': response});
  Future<List<MeetingAttendee>> attendees(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/reminders/$id/attendees');
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => MeetingAttendee.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<void> delete(String id) => _dio.delete('/reminders/$id');
}
