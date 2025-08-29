import 'package:barbearia/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:barbearia/theme.dart';
import 'package:barbearia/screens/main_navigation.dart';
import 'package:barbearia/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/utils/user_bootstrap.dart'; // << importa o helper

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SupabaseConfig.initialize(
      url: 'https://frigugklxvoawbmvbaft.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZyaWd1Z2tseHZvYXdibXZiYWZ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTU2NTc5MjIsImV4cCI6MjA3MTIzMzkyMn0.1mfabQhzGDK18Lba3QaIDuymppjhcJUl2nipwfzV_nU',
    );

    // Se já existir sessão, garante a linha do usuário na tabela `users`
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    if (hasSession) {
      await ensureUserRow();
    }
  } catch (e, st) {
    debugPrint('Erro ao inicializar o Supabase: $e');
    debugPrintStack(stackTrace: st);
  }

  runApp(const BarbeariaApp());
}

class BarbeariaApp extends StatelessWidget {
  const BarbeariaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'Barbearia',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      // Se tem sessão -> vai direto pra home; senão -> Login
      home: session == null ? const LoginScreen() : const MainNavigation(),
    );
  }
}
