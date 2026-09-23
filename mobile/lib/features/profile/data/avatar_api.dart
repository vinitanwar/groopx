import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/data/auth_api.dart';

class AvatarApi {
  AvatarApi._() {
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

  static final instance = AvatarApi._();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api/v1'),
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndUpload(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 78, maxWidth: 1024, maxHeight: 1024);
    if (picked == null) return null;
    final file = File(picked.path);
    final size = await file.length();
    if (size > 5 * 1024 * 1024) throw StateError('Photo 5 MB se chhoti honi chahiye');
    final saved = await _dio.post<Map<String, dynamic>>('/users/me/avatar/upload', data: FormData.fromMap({
      'photo': await MultipartFile.fromFile(file.path, filename: picked.name),
    }));
    return saved.data?['avatar_url']?.toString();
  }

  Future<void> remove() => _dio.delete<void>('/users/me/avatar');
}
