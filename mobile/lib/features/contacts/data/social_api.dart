import 'package:dio/dio.dart';
import '../../auth/data/auth_api.dart';

class UserOption {
  const UserOption({required this.id, required this.name, required this.username, required this.phone});
  factory UserOption.fromJson(Map<String, dynamic> json) => UserOption(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'GroopX User',
    username: json['username'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
  );
  final String id;
  final String name;
  final String username;
  final String phone;
}

class GroupMember {
  const GroupMember({required this.id, required this.name, required this.username, required this.role, required this.mine});
  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Member',
    username: json['username'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
    mine: json['mine'] as bool? ?? false,
  );
  final String id, name, username, role;
  final bool mine;
}

class GroupDetails {
  const GroupDetails({required this.id, required this.name, required this.description, required this.privacy, required this.members});
  factory GroupDetails.fromJson(Map<String, dynamic> json) => GroupDetails(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    privacy: json['privacy'] as String? ?? 'private',
    members: (json['members'] as List<dynamic>? ?? const []).map((item) => GroupMember.fromJson(item as Map<String, dynamic>)).toList(),
  );
  final String id, name, description, privacy;
  final List<GroupMember> members;
}

class CommunitySummary {
  const CommunitySummary({required this.id, required this.name, required this.description, required this.role, required this.groupCount, required this.memberCount});
  factory CommunitySummary.fromJson(Map<String, dynamic> json) => CommunitySummary(id: json['id'] as String, name: json['name'] as String? ?? 'Community', description: json['description'] as String? ?? '', role: json['role'] as String? ?? 'member', groupCount: json['group_count'] as int? ?? 0, memberCount: json['member_count'] as int? ?? 0);
  final String id, name, description, role;
  final int groupCount, memberCount;
}

class CommunityGroup {
  const CommunityGroup({required this.id, required this.name, required this.memberCount});
  factory CommunityGroup.fromJson(Map<String, dynamic> json) => CommunityGroup(id: json['id'] as String, name: json['name'] as String? ?? 'Group', memberCount: json['member_count'] as int? ?? 0);
  final String id, name;
  final int memberCount;
}

class CommunityDetails {
  const CommunityDetails({required this.id, required this.name, required this.description, required this.role, required this.groups});
  factory CommunityDetails.fromJson(Map<String, dynamic> json) => CommunityDetails(id: json['id'] as String, name: json['name'] as String? ?? 'Community', description: json['description'] as String? ?? '', role: json['role'] as String? ?? 'member', groups: (json['groups'] as List<dynamic>? ?? const []).map((item) => CommunityGroup.fromJson(item as Map<String, dynamic>)).toList());
  final String id, name, description, role;
  final List<CommunityGroup> groups;
}

class InviteJoinResult {
  const InviteJoinResult({required this.id, required this.kind});
  final String id, kind;
}

class SocialApi {
  SocialApi._() {
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
  static final instance = SocialApi._();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api/v1'),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  Future<List<UserOption>> searchUsers(String query) async {
    if (query.trim().length < 2) return const [];
    final response = await _dio.get<Map<String, dynamic>>('/users/search', queryParameters: {'q': query.trim()});
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => UserOption.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<String> saveContact({required String displayName, required String phone, required String username, required String notes}) async {
    final response = await _dio.post<Map<String, dynamic>>('/contacts', data: {
      'display_name': displayName, 'phone': phone, 'username': username, 'notes': notes,
    });
    return response.data!['conversation_id'] as String;
  }
  Future<String> createGroup({required String name, required String description, required String privacy, required List<String> memberIds}) async {
    final response = await _dio.post<Map<String, dynamic>>('/groups', data: {
      'name': name, 'description': description, 'privacy': privacy, 'member_ids': memberIds,
    });
    return response.data!['id'] as String;
  }
  Future<GroupDetails> group(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/groups/$id');
    return GroupDetails.fromJson(response.data!);
  }
  Future<void> updateGroup(String id,{required String name,required String description,required String privacy}) async {
    await _dio.patch('/groups/$id',data:{'name':name,'description':description,'privacy':privacy});
  }
  Future<void> addGroupMembers(String id, List<String> memberIds) async {
    await _dio.post('/groups/$id/members', data: {'member_ids': memberIds});
  }
  Future<void> removeGroupMember(String groupId, String userId) async {
    await _dio.delete('/groups/$groupId/members/$userId');
  }
  Future<void> updateGroupMemberRole(String groupId, String userId, String role) async {
    await _dio.patch('/groups/$groupId/members/$userId/role', data: {'role': role});
  }
  Future<String> createGroupInvite(String groupId, {int expiresInHours = 24, int maxUses = 50}) async {
    final response = await _dio.post<Map<String, dynamic>>('/groups/$groupId/invites', data: {'expires_in_hours': expiresInHours, 'max_uses': maxUses});
    return response.data!['invite_link'] as String;
  }
  Future<InviteJoinResult> joinGroupInvite(String token) async {
    final response = await _dio.post<Map<String, dynamic>>('/group-invites/$token/join');
    return InviteJoinResult(id: response.data!['group_id'] as String, kind: response.data?['kind']?.toString() ?? 'group');
  }
  Future<void> leaveGroup(String id) async { await _dio.post('/groups/$id/leave'); }
  Future<List<CommunitySummary>> communities() async {
    final response = await _dio.get<Map<String, dynamic>>('/communities');
    return (response.data?['items'] as List<dynamic>? ?? const []).map((item) => CommunitySummary.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<String> createCommunity({required String name, required String description}) async {
    final response = await _dio.post<Map<String, dynamic>>('/communities', data: {'name': name, 'description': description});
    return response.data!['id'] as String;
  }
  Future<CommunityDetails> community(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/communities/$id');
    return CommunityDetails.fromJson(response.data!);
  }
  Future<List<CommunityGroup>> manageableGroups() async {
    final response = await _dio.get<Map<String, dynamic>>('/manageable-groups');
    return (response.data?['items'] as List<dynamic>? ?? const []).map((item) => CommunityGroup.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<void> addCommunityGroup(String communityId, String groupId) async { await _dio.post('/communities/$communityId/groups', data: {'group_id': groupId}); }
  Future<void> removeCommunityGroup(String communityId, String groupId) async { await _dio.delete('/communities/$communityId/groups/$groupId'); }
  Future<void> setBlocked(String userId, bool blocked) async {
    if (blocked) { await _dio.post('/users/$userId/block'); } else { await _dio.delete('/users/$userId/block'); }
  }
  Future<List<UserOption>> blockedUsers() async {
    final response = await _dio.get<Map<String, dynamic>>('/users/blocked');
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => UserOption.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<void> reportUser(String userId, {required String conversationId, required String reason, String details = ''}) async {
    await _dio.post('/users/$userId/report', data: {'conversation_id': conversationId, 'reason': reason, 'details': details});
  }
}
