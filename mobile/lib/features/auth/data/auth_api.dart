import 'package:dio/dio.dart';

class AuthApi {
  AuthApi._();
  static final instance = AuthApi._();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api/v1'),
    connectTimeout: const Duration(seconds: 10),
  ));

  Future<void> requestOtp(String phone) async {
    await _dio.post('/auth/request-otp', data: {'phone': phone});
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async {
    final response = await _dio.post<Map<String, dynamic>>('/auth/verify-otp', data: {'phone': phone, 'code': code});
    return response.data ?? const {};
  }
}

