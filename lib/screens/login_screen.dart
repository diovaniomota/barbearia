import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import 'package:barbearia/services/auth_service.dart';
import 'package:barbearia/screens/admin/admin_navigation.dart';
import 'package:barbearia/screens/role_choice_screen.dart';
import 'package:barbearia/utils/user_bootstrap.dart';
import 'package:barbearia/utils/admin_session.dart';
import 'package:barbearia/utils/pwa_helper.dart';

const _kSavedEmail = 'login_saved_email';
// _v2: reseta marcações antigas de "dispensado" causadas pelo bug em que o
// modal podia aparecer (e ser fechado) sobre a tela de escolha cliente/admin.
const _kInstallHintDismissed = 'login_install_hint_dismissed_v2';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _checkingSession = true;
  bool _rememberEmail = false;
  bool _installModalShown = false;
  Timer? _androidInstallPoll;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
    _redirectIfLogged();
  }

  Future<void> _checkInstallHint() async {
    if (!PwaHelper.shouldPromptInstall) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_kInstallHintDismissed) ?? false;
    if (dismissed || !mounted) return;

    if (PwaHelper.isAndroid) {
      // O Chrome dispara `beforeinstallprompt` de forma assíncrona (às vezes
      // um pouco depois do primeiro frame), então espera aparecer em vez de
      // checar só uma vez. Sem isso disparar, não tem prompt nativo pra
      // acionar — não faz sentido mostrar o modal nesse caso.
      _androidInstallPoll = Timer.periodic(const Duration(milliseconds: 400), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (PwaHelper.canInstallAndroid) {
          timer.cancel();
          _showInstallModal();
        }
      });
      Future.delayed(const Duration(seconds: 8), () {
        _androidInstallPoll?.cancel();
      });
      return;
    }

    _showInstallModal();
  }

  Future<void> _markInstallDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kInstallHintDismissed, true);
  }

  void _showInstallModal() {
    if (!mounted || _installModalShown) return;
    _installModalShown = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => _InstallAppDialog(isAndroid: PwaHelper.isAndroid),
    ).then((_) => _markInstallDismissed());
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kSavedEmail) ?? '';
    if (saved.isNotEmpty && mounted) {
      setState(() {
        _emailController.text = saved;
        _rememberEmail = true;
      });
    }
  }

  Future<void> _persistEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberEmail) {
      await prefs.setString(_kSavedEmail, email);
    } else {
      await prefs.remove(_kSavedEmail);
    }
  }

  @override
  void dispose() {
    _androidInstallPoll?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Se já existe sessão, garante a linha em `users` e pula a tela de login
  Future<void> _redirectIfLogged() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // Sem sessão e sem ter passado pela escolha "cliente ou admin" nesta
      // sessão do app: provavelmente caiu direto aqui ao abrir o app (ex:
      // atalho de PWA apontando pra /admin). Volta pra escolha em vez de
      // mostrar o formulário de login vazio.
      if (!RoleChoiceScreen.visitedThisSession) {
        if (mounted) context.go('/');
        return;
      }
      if (mounted) setState(() => _checkingSession = false);
      // Só checa/mostra o convite pra instalar o app depois de confirmar que
      // vamos mesmo ficar na tela de login — senão a chamada assíncrona
      // podia terminar depois do redirect acima e o modal aparecer por
      // cima da tela de escolha "cliente ou admin".
      _checkInstallHint();
      return;
    }

    if (session.user.isAnonymous) {
      await Supabase.instance.client.auth.signOut();
      if (mounted) setState(() => _checkingSession = false);
      return;
    }

    await _navigateAfterLogin();
    if (mounted) setState(() => _checkingSession = false);
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await AuthService.signInWithEmailPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (response.user != null) {
        await _persistEmail(_emailController.text.trim());
        await ensureUserRow();
        await _navigateAfterLogin();
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getErrorMessage(error.message)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Erro inesperado. Tente novamente.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateAfterLogin() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final isAdmin = user != null && !user.isAnonymous;
      if (!mounted) return;
      if (!isAdmin) {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Acesso permitido apenas para admin.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      await AdminSession.loadFromCurrentUser();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminNavigation()),
      );
    } catch (_) {
      if (!mounted) return;
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível validar o acesso admin.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String _getErrorMessage(String error) {
    if (error.contains('Invalid login credentials')) {
      return 'Email ou senha incorretos';
    } else if (error.contains('Email not confirmed')) {
      return 'Confirme seu email antes de fazer login';
    } else if (error.contains('Too many requests')) {
      return 'Muitas tentativas. Aguarde alguns minutos.';
    }
    return 'Erro ao fazer login. Verifique suas credenciais.';
  }

  static const _bg = Color(0xFF080808);
  static const _card = Color(0xFF111111);
  static const _border = Color(0xFF222222);
  static const _gold = Color(0xFFF5C200);
  static const _text = Color(0xFFF0EDE8);
  static const _muted = Color(0xFF6B7280);


  InputDecoration _field(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      prefixIcon: Icon(icon, color: _muted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _card,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _gold, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // ── Voltar: quem caiu aqui sem querer (ex: tocou "Admin" por
              // engano na tela de cliente/admin) precisa de um jeito
              // explícito de sair — o botão "voltar" do navegador nem
              // sempre retorna pra dentro do app.
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back_rounded, color: _muted),
                  tooltip: 'Voltar',
                ),
              ),

              const SizedBox(height: 4),

              // ── Logo ────────────────────────────────────────
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                  errorBuilder: (_, __, ___) => Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _gold, width: 2),
                    ),
                    child: const Icon(
                      Icons.content_cut_rounded,
                      color: _gold,
                      size: 48,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Center(
                child: Text(
                  'Acesso administrativo',
                  style: TextStyle(color: _muted, fontSize: 14),
                ),
              ),

              const SizedBox(height: 48),

              // ── Formulário ───────────────────────────────────
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: _text),
                      decoration: _field('Email', Icons.email_outlined),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Digite seu email';
                        final ok = RegExp(
                          r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$',
                        ).hasMatch(v);
                        if (!ok) return 'Digite um email válido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _signIn(),
                      style: const TextStyle(color: _text),
                      decoration: _field(
                        'Senha',
                        Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: _muted,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Digite sua senha';
                        if (v.length < 6) return 'Mínimo 6 caracteres';
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              Row(
                children: [
                  Checkbox(
                    value: _rememberEmail,
                    onChanged: (v) =>
                        setState(() => _rememberEmail = v ?? false),
                    activeColor: _gold,
                    side: const BorderSide(color: _muted),
                  ),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _rememberEmail = !_rememberEmail),
                    child: const Text(
                      'Lembrar e-mail',
                      style: TextStyle(color: _muted, fontSize: 14),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isLoading ? null : _showForgotPasswordDialog,
                    child: const Text(
                      'Esqueci minha senha',
                      style: TextStyle(color: _gold, fontSize: 13),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
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
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: _bg,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('Entrar'),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Digite seu email para receber as instruções de recuperação:',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'Digite seu email',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (emailController.text.isNotEmpty) {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final errorColor = Theme.of(context).colorScheme.error;
                try {
                  await AuthService.resetPassword(emailController.text.trim());
                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Email de recuperação enviado!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Erro: $e'),
                      backgroundColor: errorColor,
                    ),
                  );
                }
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }
}

class _InstallAppDialog extends StatelessWidget {
  const _InstallAppDialog({required this.isAndroid});

  final bool isAndroid;

  static const _bg = Color(0xFF080808);
  static const _card = Color(0xFF111111);
  static const _border = Color(0xFF222222);
  static const _gold = Color(0xFFF5C200);
  static const _text = Color(0xFFF0EDE8);
  static const _muted = Color(0xFF6B7280);

  Widget _step(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: _gold,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _text, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isAndroid ? Icons.install_mobile : Icons.ios_share,
                  color: _gold,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Instalar o app',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (isAndroid)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Instale na tela de início pra abrir mais rápido e não '
                  'precisar logar toda vez.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
                ),
              )
            else ...[
              const SizedBox(height: 6),
              _step(1, 'Toque no ícone de compartilhar na barra do Safari.'),
              _step(2, 'Escolha "Adicionar à Tela de Início".'),
              _step(3, 'Toque em "Adicionar" no canto superior direito.'),
            ],
            const SizedBox(height: 22),
            if (isAndroid) ...[
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    PwaHelper.promptAndroidInstall();
                  },
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
                  child: const Text('Instalar'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Agora não',
                  style: TextStyle(color: _muted),
                ),
              ),
            ] else
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
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
                  child: const Text('Entendi'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
