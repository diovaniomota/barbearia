import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/screens/role_choice_screen.dart';
import 'package:barbearia/screens/main_navigation.dart';
import 'package:barbearia/screens/login_screen.dart';
import 'package:barbearia/screens/admin/admin_navigation.dart';
import 'package:barbearia/utils/auth_refresh.dart';
import 'package:barbearia/utils/admin_session.dart';

bool _hasStaffSession() {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null || session.user.isAnonymous) return false;
  // Se já validamos o papel nesta sessão do app, usa o resultado.
  if (AdminSession.loaded) return AdminSession.canAccessAdmin;
  // Ainda não carregou: sessão presente → deixa a tela validar o role.
  return true;
}

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: authRefreshNotifier,
  redirect: (BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;
    final session = Supabase.instance.client.auth.currentSession;
    final loggedIn =
        session != null && !session.user.isAnonymous;

    // Painel: exige sessão real (não anônima)
    if (loc.startsWith('/admin/dashboard')) {
      if (!loggedIn) return '/admin';
      if (AdminSession.loaded && !AdminSession.canAccessAdmin) {
        return '/admin';
      }
      return null;
    }

    // Login admin com sessão staff válida → dashboard
    if (loc == '/admin' && loggedIn && _hasStaffSession()) {
      if (AdminSession.loaded && AdminSession.canAccessAdmin) {
        return '/admin/dashboard';
      }
    }

    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const RoleChoiceScreen()),
    GoRoute(
      path: '/agendamentocliente',
      builder: (context, state) => const MainNavigation(
        initialIndex: 0,
        showSchedule: false,
        showProfile: false,
      ),
    ),
    GoRoute(path: '/admin', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/admin/dashboard',
      builder: (context, state) => const AdminNavigation(),
    ),
  ],
  errorBuilder: (context, state) => const RoleChoiceScreen(),
);
