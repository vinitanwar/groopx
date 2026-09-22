import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/data/auth_api.dart';

class BackupInfo {
  const BackupInfo({required this.id, required this.createdAt, required this.conversations, required this.messages});
  factory BackupInfo.fromJson(Map<String,dynamic> json)=>BackupInfo(id:json['id'] as String,createdAt:DateTime.parse(json['created_at'] as String).toLocal(),conversations:json['conversation_count'] as int? ?? 0,messages:json['message_count'] as int? ?? 0);
  final String id; final DateTime createdAt; final int conversations,messages;
}
class BackupApi {
  BackupApi._(){_dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler)async{final token=await AuthSession.instance.accessToken;if(token!=null)options.headers['Authorization']='Bearer $token';handler.next(options);}));}
  static final instance=BackupApi._();
  final Dio _dio=Dio(BaseOptions(baseUrl:const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080/api/v1'),connectTimeout:const Duration(seconds:15),receiveTimeout:const Duration(seconds:30)));
  Future<BackupInfo?> latest()async{final response=await _dio.get<Map<String,dynamic>>('/backups/latest');final value=response.data?['backup'];return value is Map<String,dynamic>?BackupInfo.fromJson(value):null;}
  Future<BackupInfo> create()async{final response=await _dio.post<Map<String,dynamic>>('/backups');return BackupInfo.fromJson(response.data!['backup'] as Map<String,dynamic>);}
  Future<void> restore(String id)=>_dio.post('/backups/$id/restore');
}

enum BackupFrequency { off, daily, weekly }

class BackupPreferences {
  BackupPreferences._();
  static final instance = BackupPreferences._();
  static const _setupKey = 'backup_setup_complete';
  static const _frequencyKey = 'backup_frequency';
  static const _lastAttemptKey = 'backup_last_attempt';

  Future<bool> get setupComplete async =>
      (await SharedPreferences.getInstance()).getBool(_setupKey) ?? false;

  Future<BackupFrequency> get frequency async {
    final value = (await SharedPreferences.getInstance()).getString(_frequencyKey);
    return BackupFrequency.values.firstWhere(
      (item) => item.name == value,
      orElse: () => BackupFrequency.off,
    );
  }

  Future<void> save(BackupFrequency value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_frequencyKey, value.name);
    await preferences.setBool(_setupKey, true);
  }

  Future<bool> isDue() async {
    final selected = await frequency;
    if (selected == BackupFrequency.off) return false;
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_lastAttemptKey);
    if (raw == null) return true;
    final last = DateTime.tryParse(raw);
    if (last == null) return true;
    final interval = selected == BackupFrequency.daily
        ? const Duration(days: 1)
        : const Duration(days: 7);
    return DateTime.now().difference(last) >= interval;
  }

  Future<void> markAttempt() async => (await SharedPreferences.getInstance())
      .setString(_lastAttemptKey, DateTime.now().toIso8601String());
}

class BackupScheduler {
  static bool _running = false;
  static Future<void> maybeRun() async {
    if (_running) return;
    if (!await BackupPreferences.instance.isDue()) return;
    _running = true;
    try {
      await BackupApi.instance.create();
    } catch (_) {
      // Automatic backups are retried on a later app session.
    } finally {
      await BackupPreferences.instance.markAttempt();
      _running = false;
    }
  }
}
