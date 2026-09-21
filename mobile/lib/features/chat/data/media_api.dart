import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import '../../auth/data/auth_api.dart';

class MediaApi {
  MediaApi._() {
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

  static final instance = MediaApi._();
  final Dio _dio = Dio(BaseOptions(baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api/v1'), connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 20)));

  Future<void> pickAndUpload({required String conversationId, required FileType type, required void Function(double) onProgress}) async {
    final selection = await FilePicker.platform.pickFiles(type: type, allowMultiple: false, withData: false);
    final file = selection?.files.single;
    if (file == null) return;
    if (file.path == null) throw StateError('The selected file is unavailable');
    if (file.size > 200 * 1024 * 1024) throw StateError('Maximum file size is 200 MB');
    final contentType = _contentType(file.name);
    final presign = await _dio.post<Map<String, dynamic>>('/media/presign', data: {'file_name': file.name, 'content_type': contentType, 'size': file.size});
    final data = presign.data ?? <String, dynamic>{};
    final uploadClient = Dio(BaseOptions(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 5)));
    await uploadClient.put<void>(data['upload_url'] as String, data: File(file.path!).openRead(), options: Options(headers: {'Content-Type': contentType, 'Content-Length': file.size}), onSendProgress: (sent, total) => onProgress(total <= 0 ? 0 : sent / total));
    await _dio.post('/media/complete', data: {'conversation_id': conversationId, 'object_key': data['object_key'], 'file_name': file.name, 'content_type': contentType, 'size': file.size});
    onProgress(1);
  }

  String _contentType(String name) {
    final extension = name.split('.').last.toLowerCase();
    return const {'jpg':'image/jpeg','jpeg':'image/jpeg','png':'image/png','gif':'image/gif','webp':'image/webp','mp3':'audio/mpeg','m4a':'audio/mp4','wav':'audio/wav','aac':'audio/aac','ogg':'audio/ogg','mp4':'video/mp4','mov':'video/quicktime','pdf':'application/pdf','txt':'text/plain','doc':'application/msword','docx':'application/vnd.openxmlformats-officedocument.wordprocessingml.document'}[extension] ?? 'application/octet-stream';
  }
}
