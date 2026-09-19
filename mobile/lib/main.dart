import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:groopx/core/theme/app_theme.dart';
import 'package:groopx/features/auth/presentation/welcome_screen.dart';
import 'package:groopx/features/auth/presentation/phone_screen.dart';
import 'package:groopx/features/auth/presentation/otp_screen.dart';
import 'package:groopx/features/auth/presentation/profile_setup_screen.dart';
import 'package:groopx/features/chat/presentation/chat_list_screen.dart';
import 'package:groopx/features/chat/presentation/conversation_screen.dart';
import 'package:groopx/features/groups/presentation/create_group_screen.dart';
import 'package:groopx/features/groups/presentation/group_info_screen.dart';
import 'package:groopx/features/contacts/presentation/add_contact_screen.dart';
import 'package:groopx/features/reminders/presentation/reminders_screen.dart';
import 'package:groopx/features/calls/presentation/call_screen.dart';
import 'package:groopx/features/auth/data/auth_session.dart';
import 'package:groopx/features/auth/presentation/profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthSession.instance.initialize();
  runApp(const GroopXApp());
}

final _router = GoRouter(
  initialLocation: '/',
  refreshListenable: AuthSession.instance,
  redirect: (_, state) {
    final session = AuthSession.instance;
    final location = state.matchedLocation;
    final isAuthScreen = location == '/' ||
        location == '/sign-in' ||
        location == '/sign-up' ||
        location.startsWith('/otp/');
    if (!session.isAuthenticated && !isAuthScreen) return '/';
    if (session.isAuthenticated && isAuthScreen) {
      return session.profileComplete ? '/chats' : '/profile-setup';
    }
    if (session.isAuthenticated &&
        !session.profileComplete &&
        location != '/profile-setup') return '/profile-setup';
    if (session.profileComplete && location == '/profile-setup') return '/chats';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, __) => const WelcomeScreen()),
    GoRoute(path: '/sign-in', builder: (_, __) => const PhoneScreen(mode: AuthMode.signIn)),
    GoRoute(path: '/sign-up', builder: (_, __) => const PhoneScreen(mode: AuthMode.signUp)),
    GoRoute(
      path: '/otp/:mode',
      builder: (_, state) => OtpScreen(
        mode: state.pathParameters['mode'] == 'sign-up' ? AuthMode.signUp : AuthMode.signIn,
        phone: state.uri.queryParameters['phone'] ?? '+91 98765 43210',
      ),
    ),
    GoRoute(path: '/profile-setup', builder: (_, __) => const ProfileSetupScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
    GoRoute(path: '/chat/:id', builder: (_, state) => ConversationScreen(conversationId: state.pathParameters['id']!)),
    GoRoute(path: '/groups/new', builder: (_, __) => const CreateGroupScreen()),
    GoRoute(path: '/groups/:id', builder: (_, state) => GroupInfoScreen(groupId: state.pathParameters['id']!)),
    GoRoute(path: '/contacts/new', builder: (_, __) => const AddContactScreen()),
    GoRoute(path: '/reminders', builder: (_, __) => const RemindersScreen()),
    GoRoute(path: '/call/:kind/:id', builder: (_, state) => CallScreen(callId: state.pathParameters['id']!, video: state.pathParameters['kind'] == 'video')),
  ],
);

class GroopXApp extends StatelessWidget {
  const GroopXApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'GroopX',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      );
}
