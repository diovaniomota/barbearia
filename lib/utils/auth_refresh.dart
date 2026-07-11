import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notifica o GoRouter quando a sessão Auth muda (login/logout/refresh).
///
/// Deve chamar [ensureStarted] **depois** de `Supabase.initialize`.
class AuthRefreshNotifier extends ChangeNotifier {
  StreamSubscription<AuthState>? _sub;
  bool _started = false;

  void ensureStarted() {
    if (_started) return;
    _started = true;
    try {
      _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        notifyListeners();
      });
    } catch (e) {
      debugPrint('AuthRefreshNotifier: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final authRefreshNotifier = AuthRefreshNotifier();
