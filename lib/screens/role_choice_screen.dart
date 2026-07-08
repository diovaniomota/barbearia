import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoleChoiceScreen extends StatefulWidget {
  const RoleChoiceScreen({super.key});

  // Marca que a escolha "cliente ou admin" já apareceu nesta sessão do app.
  // A tela de login usa isso pra saber se o usuário chegou em /admin
  // navegando de propósito (visitedThisSession == true) ou se caiu direto
  // ali ao abrir o app (ex: atalho de PWA apontando pra /admin) — nesse
  // segundo caso, sem sessão ativa, deve voltar pra esta tela em vez de
  // mostrar o formulário de login vazio.
  static bool visitedThisSession = false;

  @override
  State<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends State<RoleChoiceScreen> {
  static const _bg = Color(0xFF080808);
  static const _gold = Color(0xFFF5C200);
  static const _text = Color(0xFFF0EDE8);

  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  // Se o atalho instalado abre em "/" e o usuário já logou como admin antes,
  // pula direto pro painel — não faz sentido pedir "cliente ou admin?" de
  // novo pra quem já está autenticado.
  void _checkSession() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && !session.user.isAnonymous) {
      context.go('/admin');
      return;
    }
    RoleChoiceScreen.visitedThisSession = true;
    setState(() => _checkingSession = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minHeight = constraints.maxHeight > 48
                ? constraints.maxHeight - 48
                : 0.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo
                        Center(
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 110,
                            height: 110,
                            errorBuilder: (_, __, ___) => Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: _gold, width: 2),
                              ),
                              child: const Icon(
                                Icons.content_cut_rounded,
                                color: _gold,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        const Text(
                          'Você é cliente\nou admin?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _text,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Selecione para continuar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _text.withValues(alpha: 0.4),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Botão Cliente
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: _bg,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: () {
                              // signOut em background: o await aqui fazia o botão
                              // "não responder" em rede lenta (a navegação esperava
                              // a chamada de rede do logout terminar).
                              try {
                                Supabase.instance.client.auth
                                    .signOut()
                                    .catchError((_) {});
                              } catch (_) {}
                              context.go('/agendamentocliente');
                            },
                            child: const Text('Cliente'),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Botão Admin
                        SizedBox(
                          height: 54,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _gold,
                              side: const BorderSide(color: _gold, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () {
                              context.go('/admin');
                            },
                            child: const Text('Admin'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
