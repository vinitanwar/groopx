import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:groopx/core/theme/app_theme.dart';
import 'package:groopx/features/auth/presentation/welcome_screen.dart';
import 'package:groopx/features/auth/presentation/phone_screen.dart';
import 'package:groopx/features/auth/presentation/otp_screen.dart';
import 'package:groopx/features/auth/presentation/profile_setup_screen.dart';
import 'package:groopx/features/chat/presentation/chat_list_screen.dart';
import 'package:groopx/features/chat/presentation/conversation_screen.dart';
import 'package:groopx/features/chat/presentation/message_search_screen.dart';
import 'package:groopx/features/chat/presentation/starred_messages_screen.dart';
import 'package:groopx/features/chat/presentation/pinned_messages_screen.dart';
import 'package:groopx/features/chat/presentation/disappearing_messages_screen.dart';
import 'package:groopx/features/chat/presentation/scheduled_messages_screen.dart';
import 'package:groopx/features/chat/presentation/message_info_screen.dart';
import 'package:groopx/features/groups/presentation/create_group_screen.dart';
import 'package:groopx/features/groups/presentation/group_info_screen.dart';
import 'package:groopx/features/groups/presentation/group_members_screen.dart';
import 'package:groopx/features/groups/presentation/group_join_requests_screen.dart';
import 'package:groopx/features/groups/presentation/group_invites_screen.dart';
import 'package:groopx/features/groups/presentation/join_group_screen.dart';
import 'package:groopx/features/groups/presentation/invite_code_screen.dart';
import 'package:groopx/features/groups/presentation/communities_screen.dart';
import 'package:groopx/features/groups/presentation/community_details_screen.dart';
import 'package:groopx/features/groups/presentation/create_community_screen.dart';
import 'package:groopx/features/groups/presentation/edit_community_screen.dart';
import 'package:groopx/features/contacts/presentation/add_contact_screen.dart';
import 'package:groopx/features/reminders/presentation/reminders_screen.dart';
import 'package:groopx/features/calls/presentation/call_screen.dart';
import 'package:groopx/features/calls/presentation/call_history_screen.dart';
import 'package:groopx/features/calls/presentation/incoming_call_screen.dart';
import 'package:groopx/features/calls/data/call_api.dart';
import 'package:groopx/features/auth/data/auth_api.dart';
import 'package:groopx/features/notifications/presentation/notifications_screen.dart';
import 'package:groopx/features/profile/presentation/profile_screen.dart';
import 'package:groopx/features/profile/presentation/blocked_users_screen.dart';
import 'package:groopx/features/profile/presentation/edit_profile_screen.dart';
import 'package:groopx/features/profile/presentation/profile_settings_screen.dart';
import 'package:groopx/features/profile/presentation/account_security_screen.dart';
import 'package:groopx/features/status/presentation/status_screen.dart';
import 'package:groopx/features/status/presentation/status_privacy_screen.dart';
import 'package:groopx/features/groups/presentation/edit_group_screen.dart';
import 'package:groopx/features/chat/presentation/shared_media_screen.dart';
import 'package:groopx/features/chat/presentation/attachment_preview_screen.dart';
import 'package:groopx/features/profile/presentation/data_storage_screen.dart';
import 'package:groopx/features/profile/presentation/backup_setup_screen.dart';
import 'package:groopx/features/profile/presentation/help_about_screen.dart';
import 'package:groopx/features/profile/presentation/avatar_preview_screen.dart';
import 'package:groopx/features/notifications/presentation/notification_detail_screen.dart';
import 'package:groopx/features/notifications/data/notification_api.dart';
import 'package:groopx/features/contacts/presentation/contact_info_screen.dart';
import 'package:groopx/features/profile/presentation/linked_devices_screen.dart';
import 'package:groopx/features/notifications/data/push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:groopx/features/chat/data/presence_socket.dart';
import 'package:groopx/features/chat/data/live_location_service.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  var hasSession = false;
  try {
    hasSession = await AuthSession.instance.hasSession.timeout(
      const Duration(seconds: 3),
    );
  } catch (_) {
    // A stale Android keystore entry must never keep the app on its native
    // launch screen. Fall back to authentication and let the user sign in.
  }
  runApp(GroopXApp(initialLocation: hasSession ? '/chats' : '/'));
  if (hasSession) {
    unawaited(LiveLocationService.instance.initialize().catchError((_) {}));
  }
}

GoRouter _createRouter(String initialLocation) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (_, __) => const WelcomeScreen()),
    GoRoute(path: '/sign-in', builder: (_, __) => const PhoneScreen(mode: AuthMode.signIn)),
    GoRoute(path: '/sign-up', builder: (_, __) => const PhoneScreen(mode: AuthMode.signUp)),
    GoRoute(
      path: '/otp/:mode',
      builder: (_, state) => OtpScreen(
        mode: state.pathParameters['mode'] == 'sign-up' ? AuthMode.signUp : AuthMode.signIn,
        phone: state.uri.queryParameters['phone'] ?? '',
      ),
    ),
    GoRoute(path: '/profile-setup', builder: (_, __) => const ProfileSetupScreen()),
    GoRoute(path: '/backup-setup', builder: (_, state) => BackupSetupScreen(nextRoute: state.uri.queryParameters['next'] ?? '/chats')),
    GoRoute(path: '/invite-code', builder: (_, __) => const InviteCodeScreen()),
    GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
    GoRoute(path: '/chat/:id', builder: (_, state) => ConversationScreen(conversationId: state.pathParameters['id']!,initialMessageId:state.uri.queryParameters['message'])),
    GoRoute(path: '/chat/:id/search', builder: (_, state) => MessageSearchScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path: '/chat/:id/starred', builder: (_, state) => StarredMessagesScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path: '/chat/:id/pinned', builder: (_, state) => PinnedMessagesScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path: '/chat/:id/disappearing', builder: (_, state) => DisappearingMessagesScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path: '/chat/:id/scheduled', builder: (_, state) => ScheduledMessagesScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path: '/message/:id/info', builder: (_, state) => MessageInfoScreen(messageId: state.pathParameters['id']!)),
    GoRoute(path: '/groups/new', builder: (_, __) => const CreateGroupScreen()),
    GoRoute(path: '/groups/:id/join-requests', builder: (_, state) => GroupJoinRequestsScreen(groupId: state.pathParameters['id']!)),
    GoRoute(path: '/groups/:id/invites', builder: (_, state) => GroupInvitesScreen(groupId: state.pathParameters['id']!)),
    GoRoute(path: '/groups/:id/members', builder: (_, state) => GroupMembersScreen(groupId: state.pathParameters['id']!)),
    GoRoute(path: '/groups/:id', builder: (_, state) => GroupInfoScreen(groupId: state.pathParameters['id']!)),
    GoRoute(path: '/groups/:id/edit', builder: (_, state) => EditGroupScreen(groupId: state.pathParameters['id']!)),
    GoRoute(path: '/join/:token', builder: (_, state) => JoinGroupScreen(token: state.pathParameters['token']!)),
    GoRoute(path: '/communities', builder: (_, __) => const CommunitiesScreen()),
    GoRoute(path: '/communities/new', builder: (_, __) => const CreateCommunityScreen()),
    GoRoute(path: '/communities/:id/edit', builder: (_, state) => EditCommunityScreen(communityId: state.pathParameters['id']!)),
    GoRoute(path: '/communities/:id/members', builder: (_, state) => GroupMembersScreen(groupId: state.pathParameters['id']!, title: 'Community Members', scopeLabel: 'community')),
    GoRoute(path: '/communities/:id/invites', builder: (_, state) => GroupInvitesScreen(groupId: state.pathParameters['id']!, title: 'Community Invite Links', scopeLabel: 'community')),
    GoRoute(path: '/communities/:id', builder: (_, state) => CommunityDetailsScreen(communityId: state.pathParameters['id']!)),
    GoRoute(path: '/contacts/new', builder: (_, __) => const AddContactScreen()),
    GoRoute(path: '/reminders', builder: (_, __) => const RemindersScreen()),
    GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    GoRoute(path: '/notifications/detail', builder: (_, state) => NotificationDetailScreen(item:state.extra! as NotificationItem)),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/profile/edit', builder: (_, __) => const EditProfileScreen()),
    GoRoute(path: '/profile/privacy', builder: (_, __) => const PrivacySettingsScreen()),
    GoRoute(path: '/profile/notifications', builder: (_, __) => const NotificationSettingsScreen()),
    GoRoute(path: '/profile/account', builder: (_, __) => const AccountSecurityScreen()),
    GoRoute(path: '/profile/devices', builder: (_, __) => const LinkedDevicesScreen()),
    GoRoute(path: '/blocked-users', builder: (_, __) => const BlockedUsersScreen()),
    GoRoute(path: '/statuses', builder: (_, __) => const StatusScreen()),
    GoRoute(path: '/statuses/privacy', builder: (_, __) => const StatusPrivacyScreen()),
    GoRoute(path: '/calls', builder: (_, __) => const CallHistoryScreen()),
    GoRoute(path: '/chat/:id/media', builder: (_, state) => SharedMediaScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path:'/attachment',builder:(_,state){final data=state.extra! as Map<String,String>;return AttachmentPreviewScreen(kind:data['kind']??'file',name:data['name']??'Attachment',url:data['url']??'',oneTime:data['one_time']=='true');}),
    GoRoute(path: '/profile/storage', builder: (_, __) => const DataStorageScreen()),
    GoRoute(path: '/profile/help', builder: (_, __) => const HelpAboutScreen()),
    GoRoute(path: '/profile/avatar', builder: (_, state) {final data=state.extra! as Map<String,String>;return AvatarPreviewScreen(name:data['name']??'Profile photo',url:data['url']??'');}),
    GoRoute(path: '/contact/:id', builder: (_, state) => ContactInfoScreen(conversationId:state.pathParameters['id']!)),
    GoRoute(path: '/call/:kind/:id', builder: (_, state) => CallScreen(callId: state.pathParameters['id']!, video: state.pathParameters['kind'] == 'video', reminderId:state.uri.queryParameters['meeting']??'',meetingTitle:state.uri.queryParameters['title']??'')),
    GoRoute(path: '/calls/:kind/:id/incoming', builder: (_, state) {final meeting=state.uri.queryParameters['meeting']??'';return IncomingCallScreen(callId:state.pathParameters['id']!,video:state.pathParameters['kind']=='video',caller:state.uri.queryParameters['caller']??'GroopX user',meetingTitle:state.uri.queryParameters['title']??'',reminderId:meeting,keepJoinable:meeting.isNotEmpty||state.uri.queryParameters['group']=='1');}),
    GoRoute(path: '/calls/:kind/:id/join', builder: (_, state) => CallScreen(callId: state.pathParameters['id']!, video: state.pathParameters['kind'] == 'video', joinExisting: true,reminderId:state.uri.queryParameters['meeting']??'',meetingTitle:state.uri.queryParameters['title']??'')),
  ],
);

class GroopXApp extends StatefulWidget {
  const GroopXApp({super.key, this.initialLocation = '/'});
  final String initialLocation;

  @override
  State<GroopXApp> createState() => _GroopXAppState();
}

class _GroopXAppState extends State<GroopXApp> {
  late final GoRouter router = _createRouter(widget.initialLocation);
  StreamSubscription<Map<String,dynamic>>? globalSubscription;
  String? lastIncomingCallId;

  @override
  void initState() {
    super.initState();
    globalSubscription=PresenceSocket.instance.events.listen(_handleGlobalEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => PushService.initialize(onOpen: _openPush, onForeground: _showForeground));
    if(widget.initialLocation!='/') PresenceSocket.instance.start();
  }

  @override void dispose(){globalSubscription?.cancel();PresenceSocket.instance.stop();super.dispose();}

  void _handleGlobalEvent(Map<String,dynamic> data){if(data['type']=='incoming_call')_openIncomingCall(data);else if(data['type']=='call_update')NotificationCenter.instance.refresh();else if(data['type']=='live_location_update')LiveLocationService.instance.handleRealtimeEvent(data);}
  void _openIncomingCall(Map<String,dynamic> data){final callID=data['call_id']?.toString();if(callID?.isNotEmpty!=true||callID==lastIncomingCallId)return;lastIncomingCallId=callID;final kind=data['kind']?.toString()=='video'?'video':'audio';final caller=Uri.encodeComponent(data['caller']?.toString()??'GroopX user');final title=Uri.encodeComponent(data['meeting_title']?.toString()??'');final meeting=Uri.encodeComponent(data['reminder_id']?.toString()??'');final group=data['group_call']==true||data['group_call']?.toString()=='true';router.go('/calls/$kind/$callID/incoming?caller=$caller&title=$title&meeting=$meeting&group=${group?'1':'0'}');}

  Future<void> _openPush(Map<String, dynamic> data) async {
    final callID=data['call_id']?.toString(), conversationID=data['conversation_id']?.toString(), messageID=data['message_id']?.toString(), groupID=data['group_id']?.toString();
    if(callID?.isNotEmpty==true){
      try{
        final call=await CallApi.instance.status(callID!);
        if(call.status=='ringing'){_openIncomingCall({...data,'kind':call.kind});}
        else if(call.status=='answered'){final meeting=Uri.encodeComponent(data['reminder_id']?.toString()??'');final title=Uri.encodeComponent(data['meeting_title']?.toString()??'');router.go('/calls/${call.kind}/$callID/join?meeting=$meeting&title=$title');}
        else{router.go('/calls');}
      }catch(_){router.go('/calls');}
    }
    else if(data['type']?.toString()=='meeting_invite'||data['type']?.toString()=='meeting_response'||data['type']?.toString()=='meeting_update'||data['type']?.toString()=='meeting_cancelled'){
      router.go('/reminders');
    }
    else if(data['type']?.toString()=='reminder'){
      if(data['item_type']?.toString()=='meeting'&&conversationID?.isNotEmpty==true){final kind=data['call_kind']?.toString()=='audio'?'audio':'video';final meeting=Uri.encodeComponent(data['reminder_id']?.toString()??'');final title=Uri.encodeComponent(data['meeting_title']?.toString()??'');router.go('/call/$kind/$conversationID?meeting=$meeting&title=$title');}
      else{router.go('/reminders');}
    }
    else if(data['type']?.toString()=='group_join_request'&&groupID?.isNotEmpty==true){router.go('/groups/$groupID/join-requests');}
    else if(data['type']?.toString()=='group_join_approved'&&groupID?.isNotEmpty==true){router.go('/groups/$groupID');}
    else if(data['type']?.toString()=='group_join_rejected'){router.go('/notifications');}
    else if(conversationID?.isNotEmpty==true){final target=messageID?.isNotEmpty==true?'?message=${Uri.encodeQueryComponent(messageID!)}':'';router.go('/chat/$conversationID$target');}
    else{router.go('/notifications');}
  }

  void _showForeground(String title,String body,Map<String,dynamic> data){NotificationCenter.instance.refresh();if(data['call_id']?.toString().isNotEmpty==true){_openPush(data);return;}final context=rootNavigatorKey.currentContext;if(context!=null)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$title\n$body'),action:SnackBarAction(label:data['type']?.toString()=='reminder'&&data['item_type']?.toString()=='meeting'?'Start':'View',onPressed:()=>unawaited(_openPush(data)))));}

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'GroopX',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      );
}
