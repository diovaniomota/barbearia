import 'package:flutter/material.dart';
import 'package:barbearia/theme.dart';
import 'package:barbearia/screens/role_choice_screen.dart';
import 'package:barbearia/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/utils/user_bootstrap.dart'; // << importa o helper
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');

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
    return MaterialApp(
      title: 'Barbearia',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: const RoleChoiceScreen(),
    );
  }
}
