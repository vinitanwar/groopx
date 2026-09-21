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
    final picked = await _picker.pickImage(source: source, imageQuality: 82, maxWidth: 1600, maxHeight: 1600);
    if (picked == null) return null;
    final file = File(picked.path);
    final size = await file.length();
    if (size > 10 * 1024 * 1024) throw StateError('Photo 10 MB se chhoti honi chahiye');
    final contentType = _contentType(picked.name);

    final presign = await _dio.post<Map<String, dynamic>>('/media/presign', data: {
      'file_name': picked.name,
      'content_type': contentType,
      'size': size,
    });
    final uploadURL = presign.data?['upload_url']?.toString();
    final objectKey = presign.data?['object_key']?.toString();
    if (uploadURL == null || objectKey == null) throw StateError('Photo upload prepare nahi hua');

    await Dio().put<void>(uploadURL,
        data: file.openRead(),
        options: Options(headers: {'Content-Type': contentType, 'Content-Length': size}));
    final saved = await _dio.put<Map<String, dynamic>>('/users/me/avatar', data: {
      'object_key': objectKey,
      'file_name': picked.name,
      'content_type': contentType,
      'size': size,
    });
    return saved.data?['avatar_url']?.toString();
  }

  Future<void> remove() => _dio.delete<void>('/users/me/avatar');

  String _contentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}
