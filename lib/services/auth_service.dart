import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/supabase/supabase_config.dart';

class AuthService {
  static SupabaseClient get _client => SupabaseConfig.client;

  // Verificar se o usuário está logado
  static bool get isLoggedIn => _client.auth.currentUser != null;

  // Obter o usuário atual
  static User? get currentUser => _client.auth.currentUser;

  // Stream do estado de autenticação
  static Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // Login com email e senha
  static Future<AuthResponse> signInWithEmailPassword(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Registro de novo usuário
  static Future<AuthResponse> signUpWithEmailPassword(
    String email, 
    String password, 
    String fullName,
  ) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Logout
  static Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  // Recuperar senha
  static Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } catch (e) {
      rethrow;
    }
  }

  // Obter o perfil do usuário
  static Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      if (currentUser == null) return null;
      
      final response = await _client
          .from('users')
          .select()
          .eq('id', currentUser!.id)
          .single();
      
      return response;
    } catch (e) {
      return null;
    }
  }

  // Atualizar o perfil do usuário
  static Future<void> updateUserProfile(Map<String, dynamic> userData) async {
    try {
      if (currentUser == null) throw Exception('Usuário não logado');
      
      await _client
          .from('users')
          .upsert({
            'id': currentUser!.id,
            'email': currentUser!.email,
            'updated_at': DateTime.now().toIso8601String(),
            ...userData,
          });
    } catch (e) {
      rethrow;
    }
  }
}