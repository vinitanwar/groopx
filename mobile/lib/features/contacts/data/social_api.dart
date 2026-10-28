import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/data/auth_api.dart';

class UserOption {
  const UserOption({required this.id, required this.name, required this.username, required this.phone, required this.avatarUrl});
  factory UserOption.fromJson(Map<String, dynamic> json) => UserOption(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'GroopX User',
    username: json['username'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    avatarUrl: json['avatar_url'] as String? ?? '',
  );
  final String id;
  final String name;
  final String username;
  final String phone;
  final String avatarUrl;
}

class GroupMember {
  const GroupMember({required this.id, required this.name, required this.profileName, required this.displayName, required this.username, required this.mention, required this.role, required this.mine, this.avatarUrl = ''});
  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Member',
    profileName: (json['profile_name'] as String?) ?? (json['name'] as String?) ?? 'Member',
    displayName: json['display_name'] as String? ?? '',
    username: json['username'] as String? ?? '',
    mention: json['mention'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
    mine: json['mine'] as bool? ?? false,
    avatarUrl: json['avatar_url'] as String? ?? '',
  );
  final String id, name, profileName, displayName, username, mention, role, avatarUrl;
  final bool mine;
}

class GroupMemberPage {
  const GroupMemberPage({required this.items, required this.total, required this.limit, required this.offset, required this.hasMore, required this.admin, required this.canAddMembers});
  factory GroupMemberPage.fromJson(Map<String, dynamic> json) => GroupMemberPage(
    items: (json['items'] as List<dynamic>? ?? const []).map((item) => GroupMember.fromJson(item as Map<String, dynamic>)).toList(),
    total: (json['total'] as num?)?.toInt() ?? 0,
    limit: (json['limit'] as num?)?.toInt() ?? 20,
    offset: (json['offset'] as num?)?.toInt() ?? 0,
    hasMore: json['has_more'] as bool? ?? false,
    admin: json['admin'] as bool? ?? false,
    canAddMembers: json['can_add_members'] as bool? ?? false,
  );
  final List<GroupMember> items;
  final int total, limit, offset;
  final bool hasMore, admin, canAddMembers;
}

class GroupDetails {
  const GroupDetails({required this.id, required this.name, required this.description, required this.privacy, required this.avatarUrl, required this.members, this.announcementOnly = false, this.joinApprovalRequired = false, this.membersCanEditInfo = false, this.membersCanAddMembers = false, this.admin = false, this.canEditInfo = false, this.canAddMembers = false, this.pendingJoinRequests = 0});
  factory GroupDetails.fromJson(Map<String, dynamic> json) => GroupDetails(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    privacy: json['privacy'] as String? ?? 'private',
    avatarUrl: json['avatar_url'] as String? ?? '',
    members: (json['members'] as List<dynamic>? ?? const []).map((item) => GroupMember.fromJson(item as Map<String, dynamic>)).toList(),
    announcementOnly: json['announcement_only'] as bool? ?? false,
    joinApprovalRequired: json['join_approval_required'] as bool? ?? false,
    membersCanEditInfo: json['members_can_edit_info'] as bool? ?? false,
    membersCanAddMembers: json['members_can_add_members'] as bool? ?? false,
    admin: json['admin'] as bool? ?? false,
    canEditInfo: json['can_edit_info'] as bool? ?? false,
    canAddMembers: json['can_add_members'] as bool? ?? false,
    pendingJoinRequests: (json['pending_join_requests'] as num?)?.toInt() ?? 0,
  );
  final String id, name, description, privacy, avatarUrl;
  final List<GroupMember> members;
  final bool announcementOnly, joinApprovalRequired, membersCanEditInfo, membersCanAddMembers, admin, canEditInfo, canAddMembers;
  final int pendingJoinRequests;
}

class GroupJoinRequest {
  const GroupJoinRequest({required this.id, required this.userId, required this.name, required this.username, required this.avatarUrl, required this.requestedAt});
  factory GroupJoinRequest.fromJson(Map<String, dynamic> json) => GroupJoinRequest(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    name: json['name'] as String? ?? 'GroopX user',
    username: json['username'] as String? ?? '',
    avatarUrl: json['avatar_url'] as String? ?? '',
    requestedAt: DateTime.parse(json['requested_at'] as String).toLocal(),
  );
  final String id, userId, name, username, avatarUrl;
  final DateTime requestedAt;
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
  const CommunityDetails({required this.id, required this.name, required this.description, required this.role, required this.groups, this.memberCount = 0});
  factory CommunityDetails.fromJson(Map<String, dynamic> json) => CommunityDetails(id: json['id'] as String, name: json['name'] as String? ?? 'Community', description: json['description'] as String? ?? '', role: json['role'] as String? ?? 'member', groups: (json['groups'] as List<dynamic>? ?? const []).map((item) => CommunityGroup.fromJson(item as Map<String, dynamic>)).toList(), memberCount: (json['member_count'] as num?)?.toInt() ?? 0);
  final String id, name, description, role;
  final List<CommunityGroup> groups;
  final int memberCount;
}

class InviteJoinResult {
  const InviteJoinResult({required this.id, required this.kind, required this.status, required this.message, this.requestId = ''});
  factory InviteJoinResult.fromJson(Map<String, dynamic> json) => InviteJoinResult(
    id: json['group_id'] as String,
    kind: json['kind']?.toString() ?? 'group',
    status: json['status']?.toString() ?? 'joined',
    message: json['message']?.toString() ?? '',
    requestId: json['request_id']?.toString() ?? '',
  );
  final String id, kind, status, message, requestId;
  bool get pending => status == 'pending';
}

class GroupInvite {
  const GroupInvite({required this.id, required this.creatorName, required this.expiresAt, required this.createdAt, required this.maxUses, required this.useCount, required this.status});
  factory GroupInvite.fromJson(Map<String, dynamic> json) => GroupInvite(
    id: json['id'] as String,
    creatorName: json['creator_name'] as String? ?? 'Former member',
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    maxUses: (json['max_uses'] as num?)?.toInt() ?? 0,
    useCount: (json['use_count'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'expired',
  );
  final String id, creatorName, status;
  final DateTime expiresAt, createdAt;
  final int maxUses, useCount;
  bool get active => status == 'active';
  int get remainingUses => (maxUses - useCount).clamp(0, maxUses).toInt();
}

class CreatedGroupInvite {
  const CreatedGroupInvite({required this.id, required this.link, required this.expiresAt, required this.createdAt, required this.maxUses});
  factory CreatedGroupInvite.fromJson(Map<String, dynamic> json) => CreatedGroupInvite(
    id: json['id'] as String,
    link: json['invite_link'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    maxUses: (json['max_uses'] as num?)?.toInt() ?? 0,
  );
  final String id, link;
  final DateTime expiresAt, createdAt;
  final int maxUses;
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
  final ImagePicker _imagePicker = ImagePicker();
  Future<List<UserOption>> searchUsers(String query) async {
    if (query.trim().length < 2) return const [];
    final response = await _dio.get<Map<String, dynamic>>('/users/search', queryParameters: {'q': query.trim()});
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => UserOption.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<List<UserOption>> discoverContacts(List<String> phones) async {
    if (phones.isEmpty) return const [];
    final response = await _dio.post<Map<String, dynamic>>('/contacts/discover', data: {'phones': phones.take(500).toList()});
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => UserOption.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<String> saveContact({String? contactUserId, required String displayName, required String phone, required String username, required String notes}) async {
    final response = await _dio.post<Map<String, dynamic>>('/contacts', data: {
      if (contactUserId != null) 'contact_user_id': contactUserId,
      'display_name': displayName, 'phone': phone, 'username': username, 'notes': notes,
    });
    return response.data!['conversation_id'] as String;
  }
  Future<String> createGroup({required String name, required String description, required String privacy, required List<String> memberIds, bool announcementOnly = false, bool joinApprovalRequired = false, bool membersCanEditInfo = false, bool membersCanAddMembers = false}) async {
    final response = await _dio.post<Map<String, dynamic>>('/groups', data: {
      'name': name, 'description': description, 'privacy': privacy, 'member_ids': memberIds, 'announcement_only': announcementOnly, 'join_approval_required': joinApprovalRequired, 'members_can_edit_info': membersCanEditInfo, 'members_can_add_members': membersCanAddMembers,
    });
    return response.data!['id'] as String;
  }
  Future<GroupDetails> group(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/groups/$id');
    return GroupDetails.fromJson(response.data!);
  }
  Future<void> updateGroup(String id,{required String name,required String description,required String privacy,required bool announcementOnly,required bool joinApprovalRequired,required bool membersCanEditInfo,required bool membersCanAddMembers}) async {
    await _dio.patch('/groups/$id',data:{'name':name,'description':description,'privacy':privacy,'announcement_only':announcementOnly,'join_approval_required':joinApprovalRequired,'members_can_edit_info':membersCanEditInfo,'members_can_add_members':membersCanAddMembers});
  }
  Future<String?> pickAndUploadGroupAvatar(String id, ImageSource source) async {
    final picked=await _imagePicker.pickImage(source:source,imageQuality:78,maxWidth:1024,maxHeight:1024);if(picked==null)return null;
    final file=File(picked.path);if(await file.length()>5*1024*1024)throw StateError('Photo 5 MB se chhoti honi chahiye');
    final response=await _dio.post<Map<String,dynamic>>('/groups/$id/avatar',data:FormData.fromMap({'photo':await MultipartFile.fromFile(file.path,filename:picked.name)}));
    return response.data?['avatar_url']?.toString();
  }
  Future<void> removeGroupAvatar(String id) async { await _dio.delete('/groups/$id/avatar'); }
  Future<void> addGroupMembers(String id, List<String> memberIds) async {
    await _dio.post('/groups/$id/members', data: {'member_ids': memberIds});
  }
  Future<GroupMemberPage> groupMembers(String id, {String query = '', String role = 'all', int limit = 20, int offset = 0}) async {
    final response = await _dio.get<Map<String, dynamic>>('/groups/$id/members', queryParameters: {'q': query.trim(), 'role': role, 'limit': limit, 'offset': offset});
    return GroupMemberPage.fromJson(response.data!);
  }
  Future<void> removeGroupMember(String groupId, String userId) async {
    await _dio.delete('/groups/$groupId/members/$userId');
  }
  Future<void> updateGroupMemberRole(String groupId, String userId, String role) async {
    await _dio.patch('/groups/$groupId/members/$userId/role', data: {'role': role});
  }
  Future<void> updateGroupMemberDisplayName(String groupId, String userId, String displayName) async {
    await _dio.patch('/groups/$groupId/members/$userId/display-name', data: {'display_name': displayName.trim()});
  }
  Future<String> createGroupInvite(String groupId, {int expiresInHours = 24, int maxUses = 50}) async {
    return (await createGroupInviteDetails(groupId, expiresInHours: expiresInHours, maxUses: maxUses)).link;
  }
  Future<CreatedGroupInvite> createGroupInviteDetails(String groupId, {int expiresInHours = 24, int maxUses = 50}) async {
    final response = await _dio.post<Map<String, dynamic>>('/groups/$groupId/invites', data: {'expires_in_hours': expiresInHours, 'max_uses': maxUses});
    return CreatedGroupInvite.fromJson(response.data!);
  }
  Future<List<GroupInvite>> groupInvites(String groupId) async {
    final response = await _dio.get<Map<String, dynamic>>('/groups/$groupId/invites');
    return (response.data?['items'] as List<dynamic>? ?? const []).map((item) => GroupInvite.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<void> revokeGroupInvite(String groupId, String inviteId) async {
    await _dio.delete('/groups/$groupId/invites/$inviteId');
  }
  Future<CreatedGroupInvite> resetGroupInvites(String groupId, {int expiresInHours = 24, int maxUses = 50}) async {
    final response = await _dio.post<Map<String, dynamic>>('/groups/$groupId/invites/reset', data: {'expires_in_hours': expiresInHours, 'max_uses': maxUses});
    return CreatedGroupInvite.fromJson(response.data!);
  }
  Future<InviteJoinResult> joinGroupInvite(String token) async {
    final response = await _dio.post<Map<String, dynamic>>('/group-invites/$token/join');
    return InviteJoinResult.fromJson(response.data!);
  }
  Future<List<GroupJoinRequest>> groupJoinRequests(String groupId) async {
    final response = await _dio.get<Map<String, dynamic>>('/groups/$groupId/join-requests');
    return (response.data?['items'] as List<dynamic>? ?? const []).map((item) => GroupJoinRequest.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<void> reviewGroupJoinRequest(String groupId, String requestId, {required bool approve}) async {
    await _dio.patch('/groups/$groupId/join-requests/$requestId', data: {'action': approve ? 'approve' : 'reject'});
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
  Future<void> updateCommunity(String id, {required String name, required String description}) async {
    await _dio.patch('/communities/$id', data: {'name': name.trim(), 'description': description.trim()});
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
