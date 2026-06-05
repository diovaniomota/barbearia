import 'package:flutter/material.dart';
import 'package:barbearia/theme.dart';
import 'package:barbearia/router.dart';
import 'package:barbearia/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/utils/user_bootstrap.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); // URLs limpas: /agendamentocliente em vez de /#/agendamentocliente
  await initializeDateFormatting('pt_BR');

  try {
    await SupabaseConfig.initialize(
      url: 'https://uebvtbgvsyzbyzdilren.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVlYnZ0Ymd2c3l6Ynl6ZGlscmVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxNzM4MTMsImV4cCI6MjA5NTc0OTgxM30.KilnvJtRntdp3LO_mrTKBxpVcaEgOoJSPNEjBGXsrC4',
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
    return MaterialApp.router(
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
      routerConfig: appRouter,
    );
  }
}
