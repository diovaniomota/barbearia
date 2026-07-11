import 'package:supabase_flutter/supabase_flutter.dart';

/// Sessão do painel admin.
///
/// - Super-admin (dono): [isSuperAdmin] == true → [barberId] == null (vê todos)
/// - Barbeiro: [isBarber] == true → filtra pela própria agenda
///
/// Acesso exige `users.is_admin = true` **ou** vínculo em `barbers.user_id`.
/// (Migration promove staff existente.)
class AdminSession {
  static String? barberId;
  static String? barberName;
  static bool isAdminFlag = false;
  static bool canAccessAdmin = false;
  static bool loaded = false;

  static bool get isSuperAdmin => canAccessAdmin && barberId == null;
  static bool get isBarber => barberId != null;

  /// Carrega papel a partir do usuário autenticado.
  /// Retorna true se pode entrar no painel.
  static Future<bool> loadFromCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      clear();
      loaded = true;
      return false;
    }

    bool adminFlag = false;
    try {
      final profile = await Supabase.instance.client
          .from('users')
          .select('is_admin, role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) {
        adminFlag = profile['is_admin'] == true ||
            (profile['role']?.toString() == 'admin') ||
            (profile['role']?.toString() == 'barber');
      }
    } catch (_) {
      adminFlag = false;
    }

    String? bId;
    String? bName;
    try {
      final row = await Supabase.instance.client
          .from('barbers')
          .select('id, name')
          .eq('user_id', user.id)
          .maybeSingle();
      if (row != null) {
        bId = row['id'].toString();
        bName = row['name']?.toString();
      }
    } catch (_) {}

    // Acesso: is_admin/role staff OU barbeiro linkado.
    // Fallback legado: se a coluna is_admin ainda não existe / falhou o select
    // e o usuário autenticou no /admin, permite se tiver linha em users.
    final linkedBarber = bId != null;
    var allowed = adminFlag || linkedBarber;

    if (!allowed) {
      // Compat: usuários antigos sem is_admin — se conseguirem ler users e
      // existirem, promove em memória e tenta gravar is_admin.
      try {
        final any = await Supabase.instance.client
            .from('users')
            .select('id')
            .eq('id', user.id)
            .maybeSingle();
        if (any != null) {
          allowed = true;
          try {
            await Supabase.instance.client
                .from('users')
                .update({'is_admin': true, 'role': 'admin'})
                .eq('id', user.id);
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (!allowed) {
      clear();
      loaded = true;
      return false;
    }

    isAdminFlag = adminFlag || !linkedBarber;
    if (linkedBarber) {
      barberId = bId;
      barberName = bName;
    } else {
      barberId = null;
      barberName = null;
    }
    canAccessAdmin = true;
    loaded = true;
    return true;
  }

  static void clear() {
    barberId = null;
    barberName = null;
    isAdminFlag = false;
    canAccessAdmin = false;
    loaded = false;
  }
}
