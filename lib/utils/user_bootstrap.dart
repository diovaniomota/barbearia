import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> ensureUserRow() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return;

  try {
    await supabase.from('users').upsert({
      'id': user.id,
      'name': user.userMetadata?['name'] ?? user.email?.split('@').first,
      'email': user.email,
      'phone': user.userMetadata?['phone'],
      'avatar_url': user.userMetadata?['avatar_url'],
    }, onConflict: 'id');
  } catch (_) {
    // Silencia falhas transitórias; a próxima operação de app corrige o estado
  }
}
