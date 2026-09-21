import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthSession {
  AuthSession._();
  static final instance = AuthSession._();
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'groopx_access_token';
  static const _refreshKey = 'groopx_refresh_token';
  static const _pendingInviteKey = 'groopx_pending_invite';
  Future<String?> get accessToken => _storage.read(key: _accessKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);
  Future<bool> get hasSession async => (await refreshToken)?.isNotEmpty == true;
  Future<void> save(Map<String, dynamic> payload) async {
    final access = payload['access_token'] as String?;
    final refresh = payload['refresh_token'] as String?;
    if (access != null) await _storage.write(key: _accessKey, value: access);
    if (refresh != null) await _storage.write(key: _refreshKey, value: refresh);
  }
  Future<void> savePendingInvite(String token) =>
      _storage.write(key: _pendingInviteKey, value: token);
  Future<String?> takePendingInvite() async {
    final token = await _storage.read(key: _pendingInviteKey);
    await _storage.delete(key: _pendingInviteKey);
    return token;
  }
  Future<void> clear() => _storage.deleteAll();
}

class AuthApi {
  AuthApi._() {
    _dio.options.headers['X-Device-Name'] = 'GroopX mobile app';
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.extra['authenticated'] == true) {
          final token = await AuthSession.instance.accessToken;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final request = error.requestOptions;
        if (error.response?.statusCode == 401 &&
            request.extra['authenticated'] == true &&
            request.extra['retried'] != true) {
          try {
            await refresh();
            final token = await AuthSession.instance.accessToken;
            request.headers['Authorization'] = 'Bearer $token';
            request.extra['retried'] = true;
            return handler.resolve(await _dio.fetch(request));
          } catch (_) {
            await AuthSession.instance.clear();
          }
        }
        handler.next(error);
      },
    ));
  }
  static final instance = AuthApi._();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api/v1'),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  Future<Map<String, dynamic>> requestOtp(String phone) async {
    final response = await _dio.post<Map<String, dynamic>>('/auth/request-otp', data: {'phone': phone});
    return response.data ?? <String, dynamic>{};
  }
  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async {
    final response = await _dio.post<Map<String, dynamic>>('/auth/verify-otp', data: {'phone': phone, 'code': code});
    final data = response.data ?? <String, dynamic>{};
    await AuthSession.instance.save(data);
    return data;
  }
  Future<void> refresh() async {
    final token = await AuthSession.instance.refreshToken;
    if (token == null) throw StateError('No refresh token');
    final response = await _dio.post<Map<String, dynamic>>('/auth/refresh', data: {'refresh_token': token});
    await AuthSession.instance.save(response.data ?? <String, dynamic>{});
  }
  Future<Map<String, dynamic>> currentUser() async {
    final response = await _dio.get<Map<String, dynamic>>('/users/me', options: Options(extra: {'authenticated': true}));
    return response.data ?? <String, dynamic>{};
  }
  Future<Map<String, dynamic>> updateProfile({required String fullName, required String username, String? dateOfBirth, String? gender, String? bio}) async {
    final response = await _dio.put<Map<String, dynamic>>('/users/me/profile',
      data: {'full_name': fullName, 'username': username, 'date_of_birth': dateOfBirth ?? '', 'gender': gender ?? '', 'bio': bio ?? ''},
      options: Options(extra: {'authenticated': true}),
    );
    return response.data ?? <String, dynamic>{};
  }
  Future<void> updateSettings(Map<String, bool> settings) async {
    await _dio.patch('/users/me/settings', data: settings, options: Options(extra: {'authenticated': true}));
  }
  Future<void> logout() async {
    final token = await AuthSession.instance.refreshToken;
    try {
      if (token != null) await _dio.post('/auth/logout', data: {'refresh_token': token});
    } finally {
      await AuthSession.instance.clear();
    }
  }

  Future<List<AccountSession>> sessions() async {
    final refresh = await AuthSession.instance.refreshToken;
    if (refresh == null) throw StateError('No active session');
    final response = await _dio.post<Map<String, dynamic>>('/users/me/sessions', data: {'refresh_token': refresh}, options: Options(extra: {'authenticated': true}));
    return (response.data?['items'] as List<dynamic>? ?? const []).map((item) => AccountSession.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<void> revokeSession(String id) => _dio.delete('/users/me/sessions/$id', options: Options(extra: {'authenticated': true}));

  Future<int> revokeOtherSessions() async {
    final refresh = await AuthSession.instance.refreshToken;
    if (refresh == null) throw StateError('No active session');
    final response = await _dio.post<Map<String, dynamic>>('/users/me/sessions/revoke-others', data: {'refresh_token': refresh}, options: Options(extra: {'authenticated': true}));
    return response.data?['count'] as int? ?? 0;
  }
}

class AccountSession {
  const AccountSession({required this.id, required this.deviceName, required this.userAgent, required this.ipAddress, required this.createdAt, required this.lastSeenAt, required this.expiresAt, required this.current});
  factory AccountSession.fromJson(Map<String, dynamic> json) => AccountSession(
    id: json['id'] as String,
    deviceName: json['device_name']?.toString() ?? 'GroopX device',
    userAgent: json['user_agent']?.toString() ?? '',
    ipAddress: json['ip_address']?.toString() ?? '',
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    lastSeenAt: DateTime.parse(json['last_seen_at'] as String).toLocal(),
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    current: json['current'] == true,
  );
  final String id, deviceName, userAgent, ipAddress;
  final DateTime createdAt, lastSeenAt, expiresAt;
  final bool current;
}
