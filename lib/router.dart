import 'package:go_router/go_router.dart';
import 'package:barbearia/screens/role_choice_screen.dart';
import 'package:barbearia/screens/main_navigation.dart';
import 'package:barbearia/screens/login_screen.dart';
import 'package:barbearia/screens/admin/admin_navigation.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const RoleChoiceScreen(),
    ),
    GoRoute(
      path: '/agendamentocliente',
      builder: (context, state) => const MainNavigation(
        initialIndex: 0,
        showSchedule: false,
        showProfile: false,
      ),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/admin/dashboard',
      builder: (context, state) => const AdminNavigation(),
    ),
  ],
  errorBuilder: (context, state) => const RoleChoiceScreen(),
);
