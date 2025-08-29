import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> ensureUserRow() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final existing =
      await supabase.from('users').select('id').eq('id', user.id).maybeSingle();

  if (existing == null) {
    await supabase.from('users').insert({
      'id': user.id,
      'name': user.userMetadata?['name'] ?? user.email?.split('@').first,
      'email': user.email,
      'phone': user.userMetadata?['phone'],
      'avatar_url': user.userMetadata?['avatar_url'],
    });
  }
}
