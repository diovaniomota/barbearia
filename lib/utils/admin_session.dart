import 'package:supabase_flutter/supabase_flutter.dart';

/// Guarda o papel do admin logado durante a sessão.
/// Super-admin (dono): [barberId] == null — vê todos os barbeiros.
/// Barbeiro-admin: [barberId] != null — vê apenas os próprios dados.
class AdminSession {
  static String? barberId;
  static String? barberName;

  static bool get isSuperAdmin => barberId == null;
  static bool get isBarber => barberId != null;

  /// Detecta o papel a partir do usuário atual.
  /// Deve ser chamado logo após o login e ao reabrir o app com sessão ativa.
  static Future<void> loadFromCurrentUser() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      clear();
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('barbers')
          .select('id, name')
          .eq('user_id', userId)
          .maybeSingle();
      if (row != null) {
        barberId = row['id'].toString();
        barberName = row['name']?.toString();
      } else {
        clear();
      }
    } catch (_) {
      clear();
    }
  }

  static void clear() {
    barberId = null;
    barberName = null;
  }
}
