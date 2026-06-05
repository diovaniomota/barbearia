import 'package:flutter/material.dart';
import 'package:barbearia/screens/login_screen.dart';
import 'package:barbearia/screens/main_navigation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoleChoiceScreen extends StatelessWidget {
  const RoleChoiceScreen({super.key});

  static const _bg   = Color(0xFF080808);
  static const _gold = Color(0xFFF5C200);
  static const _text = Color(0xFFF0EDE8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Image.asset(
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
                    child: const Icon(Icons.content_cut_rounded,
                        color: _gold, size: 40),
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  'Você é cliente\nou admin?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Selecione para continuar',
                  style: TextStyle(
                    color: _text.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 40),

                // Botão Cliente
                SizedBox(
                  width: double.infinity,
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
                        letterSpacing: 0.3,
                      ),
                    ),
                    onPressed: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (!context.mounted) return;
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const MainNavigation(
                            initialIndex: 0,
                            showSchedule: false,
                            showProfile: false,
                          ),
                        ),
                      );
                    },
                    child: const Text('Cliente'),
                  ),
                ),
                const SizedBox(height: 12),

                // Botão Admin
                SizedBox(
                  width: double.infinity,
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
                        letterSpacing: 0.3,
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
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
  }
}
