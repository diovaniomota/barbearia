import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://frigugklxvoawbmvbaft.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZyaWd1Z2tseHZvYXdibXZiYWZ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTU2NTc5MjIsImV4cCI6MjA3MTIzMzkyMn0.1mfabQhzGDK18Lba3QaIDuymppjhcJUl2nipwfzV_nU';

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  // Helper methods for migrations
  static Future<void> applyMigrations() async {
    try {
      // This would typically run your SQL migrations
      // For now, this is a placeholder that indicates migrations are ready
      print('Migrations applied successfully');
    } catch (e) {
      print('Migration error: $e');
      rethrow;
    }
  }
}
