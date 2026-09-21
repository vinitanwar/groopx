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
import 'package:groopx/features/groups/presentation/create_group_screen.dart';
import 'package:groopx/features/groups/presentation/group_info_screen.dart';
import 'package:groopx/features/groups/presentation/join_group_screen.dart';
import 'package:groopx/features/groups/presentation/invite_code_screen.dart';
import 'package:groopx/features/groups/presentation/communities_screen.dart';
import 'package:groopx/features/groups/presentation/community_details_screen.dart';
import 'package:groopx/features/groups/presentation/create_community_screen.dart';
import 'package:groopx/features/contacts/presentation/add_contact_screen.dart';
import 'package:groopx/features/reminders/presentation/reminders_screen.dart';
import 'package:groopx/features/calls/presentation/call_screen.dart';
import 'package:groopx/features/calls/presentation/call_history_screen.dart';
import 'package:groopx/features/calls/presentation/incoming_call_screen.dart';
import 'package:groopx/features/auth/data/auth_api.dart';
import 'package:groopx/features/notifications/presentation/notifications_screen.dart';
import 'package:groopx/features/profile/presentation/profile_screen.dart';
import 'package:groopx/features/profile/presentation/blocked_users_screen.dart';
import 'package:groopx/features/profile/presentation/edit_profile_screen.dart';
import 'package:groopx/features/profile/presentation/profile_settings_screen.dart';
import 'package:groopx/features/profile/presentation/account_security_screen.dart';
import 'package:groopx/features/status/presentation/status_screen.dart';
import 'package:groopx/features/groups/presentation/edit_group_screen.dart';
import 'package:groopx/features/chat/presentation/shared_media_screen.dart';
import 'package:groopx/features/profile/presentation/data_storage_screen.dart';
import 'package:groopx/features/profile/presentation/help_about_screen.dart';
import 'package:groopx/features/profile/presentation/avatar_preview_screen.dart';
import 'package:groopx/features/notifications/presentation/notification_detail_screen.dart';
import 'package:groopx/features/notifications/data/notification_api.dart';
import 'package:groopx/features/contacts/presentation/contact_info_screen.dart';
import 'package:groopx/features/profile/presentation/linked_devices_screen.dart';
import 'package:groopx/features/notifications/data/push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  final hasSession = await AuthSession.instance.hasSession;
  runApp(GroopXApp(initialLocation: hasSession ? '/chats' : '/'));
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
    GoRoute(path: '/invite-code', builder: (_, __) => const InviteCodeScreen()),
    GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
    GoRoute(path: '/chat/:id', builder: (_, state) => ConversationScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path: '/chat/:id/search', builder: (_, state) => MessageSearchScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path: '/groups/new', builder: (_, __) => const CreateGroupScreen()),
    GoRoute(path: '/groups/:id', builder: (_, state) => GroupInfoScreen(groupId: state.pathParameters['id']!)),
    GoRoute(path: '/groups/:id/edit', builder: (_, state) => EditGroupScreen(groupId: state.pathParameters['id']!)),
    GoRoute(path: '/join/:token', builder: (_, state) => JoinGroupScreen(token: state.pathParameters['token']!)),
    GoRoute(path: '/communities', builder: (_, __) => const CommunitiesScreen()),
    GoRoute(path: '/communities/new', builder: (_, __) => const CreateCommunityScreen()),
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
    GoRoute(path: '/calls', builder: (_, __) => const CallHistoryScreen()),
    GoRoute(path: '/chat/:id/media', builder: (_, state) => SharedMediaScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path: '/profile/storage', builder: (_, __) => const DataStorageScreen()),
    GoRoute(path: '/profile/help', builder: (_, __) => const HelpAboutScreen()),
    GoRoute(path: '/profile/avatar', builder: (_, state) {final data=state.extra! as Map<String,String>;return AvatarPreviewScreen(name:data['name']??'Profile photo',url:data['url']??'');}),
    GoRoute(path: '/contact/:id', builder: (_, state) => ContactInfoScreen(conversationId:state.pathParameters['id']!)),
    GoRoute(path: '/call/:kind/:id', builder: (_, state) => CallScreen(callId: state.pathParameters['id']!, video: state.pathParameters['kind'] == 'video')),
    GoRoute(path: '/calls/:kind/:id/incoming', builder: (_, state) => IncomingCallScreen(callId:state.pathParameters['id']!,video:state.pathParameters['kind']=='video',caller:state.uri.queryParameters['caller']??'GroopX user')),
    GoRoute(path: '/calls/:kind/:id/join', builder: (_, state) => CallScreen(callId: state.pathParameters['id']!, video: state.pathParameters['kind'] == 'video', joinExisting: true)),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => PushService.initialize(onOpen: _openPush, onForeground: _showForeground));
  }

  void _openPush(Map<String, dynamic> data) {
    final callID=data['call_id']?.toString(), conversationID=data['conversation_id']?.toString();
    if(callID?.isNotEmpty==true){final kind=data['kind']?.toString()=='video'?'video':'audio';final caller=Uri.encodeComponent(data['title']?.toString()??'GroopX user');router.go('/calls/$kind/$callID/incoming?caller=$caller');}
    else if(conversationID?.isNotEmpty==true){router.go('/chat/$conversationID');}
    else{router.go('/notifications');}
  }

  void _showForeground(String title,String body){final context=rootNavigatorKey.currentContext;if(context!=null)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$title\n$body'),action:SnackBarAction(label:'View',onPressed:()=>router.go('/notifications'))));}

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'GroopX',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      );
}
