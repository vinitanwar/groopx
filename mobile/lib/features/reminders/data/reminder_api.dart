import 'package:dio/dio.dart';

import '../../auth/data/auth_api.dart';

class ReminderItem {
  const ReminderItem({required this.id, required this.title, required this.scheduledAt, required this.status, this.notes = '', this.conversationTitle = ''});
  factory ReminderItem.fromJson(Map<String, dynamic> json) => ReminderItem(
    id: json['id'] as String,
    title: json['title'] as String,
    scheduledAt: DateTime.parse(json['scheduled_at'] as String).toLocal(),
    status: json['status'] as String? ?? 'upcoming',
    notes: json['notes'] as String? ?? '',
    conversationTitle: json['conversation_title'] as String? ?? '',
  );
  final String id, title, status, notes, conversationTitle;
  final DateTime scheduledAt;
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

  Future<List<ReminderItem>> list(String status) async {
    final response = await _dio.get<Map<String, dynamic>>('/reminders', queryParameters: {'status': status});
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => ReminderItem.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<void> create({required String title, required DateTime scheduledAt, String notes = ''}) async {
    await _dio.post('/reminders', data: {'title': title, 'scheduled_at': scheduledAt.toUtc().toIso8601String(), 'notes': notes});
  }
  Future<void> updateStatus(String id, String status) => _dio.patch('/reminders/$id', data: {'status': status});
  Future<void> delete(String id) => _dio.delete('/reminders/$id');
}
