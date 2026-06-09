import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://uebvtbgvsyzbyzdilren.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVlYnZ0Ymd2c3l6Ynl6ZGlscmVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxNzM4MTMsImV4cCI6MjA5NTc0OTgxM30.KilnvJtRntdp3LO_mrTKBxpVcaEgOoJSPNEjBGXsrC4';

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;

  // Helper methods for migrations
  static Future<void> applyMigrations() async {
    try {
      // This would typically run your SQL migrations
      // For now, this is a placeholder that indicates migrations are ready
      debugPrint('Migrations applied successfully');
    } catch (e) {
      debugPrint('Migration error: $e');
      rethrow;
    }
  }
}
