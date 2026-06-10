import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/screens/admin/dashboard_screen.dart';
import 'package:barbearia/screens/admin/services_admin_screen.dart';
import 'package:barbearia/screens/admin/barbers_admin_screen.dart';
import 'package:barbearia/screens/admin/appointments_admin_screen.dart';
import 'package:barbearia/screens/admin/financial_admin_screen.dart';
import 'package:barbearia/screens/admin/whatsapp_admin_screen.dart';
import 'package:barbearia/screens/admin/plan_clients_admin_screen.dart';
import 'package:barbearia/screens/admin/remarcar_admin_screen.dart';
import 'package:barbearia/utils/admin_session.dart';
import 'package:barbearia/screens/login_screen.dart';

class _AP {
  static const Color bg = Color(0xFF080808);
  static const Color card = Color(0xFF111111);
  static const Color border = Color(0xFF222222);
  static const Color gold = Color(0xFFF5C200);
  static const Color text = Color(0xFFF0EDE8);
  static const Color muted = Color(0xFF6B7280);
}

class AdminNavigation extends StatefulWidget {
  const AdminNavigation({super.key});

  @override
  State<AdminNavigation> createState() => _AdminNavigationState();
}

class _AdminNavigationState extends State<AdminNavigation> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;

  // Bloqueia a renderização das telas até que o papel do admin esteja carregado.
  // Evita que barbeiros vejam dados de outros quando o app reabre com sessão ativa.
  bool _sessionReady = false;

  @override
  void initState() {
    super.initState();
    _ensureSession();
  }

  /// Carrega o papel (super-admin vs barbeiro) antes de mostrar as telas.
  Future<void> _ensureSession() async {
    if (Supabase.instance.client.auth.currentUser != null) {
      await AdminSession.loadFromCurrentUser();
    }
    if (mounted) setState(() => _sessionReady = true);
  }

  static const _screens = [
    DashboardScreen(),
    AppointmentsAdminScreen(),
    FinancialAdminScreen(),
    WhatsappAdminScreen(),
  ];

  void _navTo(int index) {
    Navigator.pop(context);
    setState(() => _currentIndex = index);
  }

  void _pushScreen(Widget screen) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(data: _adminTheme, child: screen),
      ),
    );
  }

  void _showChangePasswordDialog() {
    Navigator.pop(context);
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: _adminTheme,
        child: AlertDialog(
          backgroundColor: _AP.card,
          title: const Text('Alterar senha', style: TextStyle(color: _AP.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPassCtrl,
                obscureText: true,
                style: const TextStyle(color: _AP.text),
                decoration: const InputDecoration(
                  labelText: 'Nova senha',
                  labelStyle: TextStyle(color: _AP.muted),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                style: const TextStyle(color: _AP.text),
                decoration: const InputDecoration(
                  labelText: 'Confirmar senha',
                  labelStyle: TextStyle(color: _AP.muted),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _AP.gold,
                foregroundColor: _AP.bg,
              ),
              onPressed: () async {
                if (newPassCtrl.text != confirmCtrl.text) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('As senhas não coincidem')),
                  );
                  return;
                }
                if (newPassCtrl.text.length < 6) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Mínimo 6 caracteres')),
                  );
                  return;
                }
                try {
                  await Supabase.instance.client.auth.updateUser(
                    UserAttributes(password: newPassCtrl.text),
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Senha alterada com sucesso!'),
                    ),
                  );
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Aguarda o papel ser carregado antes de montar as telas (evita vazamento de dados)
    if (!_sessionReady) {
      return Theme(
        data: _adminTheme,
        child: const Scaffold(
          backgroundColor: _AP.bg,
          body: Center(child: CircularProgressIndicator(color: _AP.gold)),
        ),
      );
    }
    return Theme(
      data: _adminTheme,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: _AP.bg,
        drawer: _buildDrawer(),
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: _AdminFloatingNav(
          currentIndex: _currentIndex,
          isBarber: AdminSession.isBarber,
          onTap: (i) {
            final menuIndex = AdminSession.isBarber ? 3 : 4;
            if (i == menuIndex) {
              _scaffoldKey.currentState?.openDrawer();
              return;
            }
            setState(() => _currentIndex = i);
          },
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final isBarber = AdminSession.isBarber;
    final displayName = isBarber
        ? (AdminSession.barberName ?? 'Barbeiro')
        : 'Admin';

    return Theme(
      data: _adminTheme,
      child: Drawer(
        backgroundColor: _AP.card,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                decoration: const BoxDecoration(
                  color: _AP.bg,
                  border: Border(bottom: BorderSide(color: _AP.border)),
                ),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 44,
                      height: 44,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.content_cut,
                        color: _AP.gold,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: _AP.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (isBarber)
                            const Text(
                              'Barbeiro',
                              style: TextStyle(color: _AP.muted, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _DrawerSection('Principal'),
              _DrawerItem(
                Icons.dashboard_outlined,
                'Dashboard',
                () => _navTo(0),
                selected: _currentIndex == 0,
              ),
              _DrawerItem(
                Icons.calendar_today_outlined,
                'Agenda',
                () => _navTo(1),
                selected: _currentIndex == 1,
              ),
              _DrawerItem(
                Icons.attach_money_outlined,
                'Caixa',
                () => _navTo(2),
                selected: _currentIndex == 2,
              ),
              if (!isBarber)
                _DrawerItem(
                  Icons.chat_bubble_outline_rounded,
                  'WhatsApp',
                  () => _navTo(3),
                  selected: _currentIndex == 3,
                ),
              const Divider(color: _AP.border, indent: 16, endIndent: 16),
              _DrawerSection('Gerenciar'),
              if (!isBarber) ...[
                _DrawerItem(
                  Icons.content_cut_outlined,
                  'Serviços',
                  () => _pushScreen(const ServicesAdminScreen()),
                ),
                _DrawerItem(
                  Icons.person_outline,
                  'Barbeiros',
                  () => _pushScreen(const BarbersAdminScreen()),
                ),
              ],
              _DrawerItem(
                Icons.card_membership_outlined,
                'Clientes Plano',
                () => _pushScreen(const PlanClientsAdminScreen()),
              ),
              _DrawerItem(
                Icons.person_off_outlined,
                'Remarcar',
                () => _pushScreen(const RemarcarAdminScreen()),
              ),
              if (isBarber) ...[
                const Divider(color: _AP.border, indent: 16, endIndent: 16),
                _DrawerSection('Minha conta'),
                _DrawerItem(
                  Icons.lock_outline_rounded,
                  'Alterar senha',
                  _showChangePasswordDialog,
                ),
              ],
              const Spacer(),
              const Divider(color: _AP.border),
              _DrawerItem(Icons.logout_rounded, 'Sair', () async {
                Navigator.pop(context);
                AdminSession.clear();
                await Supabase.instance.client.auth.signOut();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Navbar flutuante (mesmo estilo do cliente) ────────────────────────────────

class _AdminFloatingNav extends StatelessWidget {
  const _AdminFloatingNav({
    required this.currentIndex,
    required this.onTap,
    this.isBarber = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isBarber;

  static const _ownerItems = [
    _NavItem(Icons.dashboard_outlined, Icons.dashboard, 'Dash'),
    _NavItem(Icons.calendar_today_outlined, Icons.calendar_today, 'Agenda'),
    _NavItem(Icons.attach_money_outlined, Icons.attach_money, 'Caixa'),
    _NavItem(
      Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
      'WhatsApp',
    ),
    _NavItem(Icons.menu_rounded, Icons.menu_rounded, 'Menu'),
  ];

  static const _barberItems = [
    _NavItem(Icons.dashboard_outlined, Icons.dashboard, 'Dash'),
    _NavItem(Icons.calendar_today_outlined, Icons.calendar_today, 'Agenda'),
    _NavItem(Icons.attach_money_outlined, Icons.attach_money, 'Caixa'),
    _NavItem(Icons.menu_rounded, Icons.menu_rounded, 'Menu'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = isBarber ? _barberItems : _ownerItems;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _AP.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _AP.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x70000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: List.generate(items.length, (i) {
                final item = items[i];
                final selected = i == currentIndex;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selected
                                ? _AP.gold.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            selected ? item.selectedIcon : item.icon,
                            color: selected ? _AP.gold : _AP.muted,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: selected ? _AP.gold : _AP.muted,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

// ── Drawer helpers ────────────────────────────────────────────────────────────

class _DrawerSection extends StatelessWidget {
  const _DrawerSection(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: _AP.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem(this.icon, this.label, this.onTap, {this.selected = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _AP.gold.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: _AP.gold.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? _AP.gold : _AP.muted, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? _AP.gold : _AP.text,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tema escuro (idêntico ao do cliente) ──────────────────────────────────────

final _adminTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.dark(
    primary: _AP.gold,
    onPrimary: _AP.bg,
    primaryContainer: Color(0xFF241E00),
    onPrimaryContainer: _AP.gold,
    secondary: _AP.muted,
    onSecondary: _AP.bg,
    surface: _AP.card,
    onSurface: _AP.text,
    error: Color(0xFFFF6B6B),
    onError: _AP.bg,
    outline: _AP.border,
    surfaceContainerHighest: _AP.card,
    onSurfaceVariant: _AP.muted,
  ),
  scaffoldBackgroundColor: _AP.bg,
  appBarTheme: const AppBarTheme(
    backgroundColor: _AP.card,
    foregroundColor: _AP.text,
    elevation: 0,
    iconTheme: IconThemeData(color: _AP.gold),
    titleTextStyle: TextStyle(
      color: _AP.text,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  ),
  cardTheme: CardThemeData(
    color: _AP.card,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: _AP.border),
    ),
  ),
  dividerTheme: const DividerThemeData(color: _AP.border, space: 1),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: _AP.gold,
    foregroundColor: _AP.bg,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: _AP.gold,
      foregroundColor: _AP.bg,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _AP.gold,
      foregroundColor: _AP.bg,
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: _AP.gold),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _AP.card,
    labelStyle: const TextStyle(color: _AP.muted),
    hintStyle: const TextStyle(color: _AP.muted),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _AP.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _AP.gold, width: 1.5),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  ),
  dropdownMenuTheme: const DropdownMenuThemeData(
    menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(_AP.card)),
  ),
  iconTheme: const IconThemeData(color: _AP.muted),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: _AP.text),
    bodyMedium: TextStyle(color: _AP.text),
    bodySmall: TextStyle(color: _AP.muted),
    titleLarge: TextStyle(color: _AP.text),
    titleMedium: TextStyle(color: _AP.text),
    titleSmall: TextStyle(color: _AP.text),
    labelSmall: TextStyle(color: _AP.muted),
    labelMedium: TextStyle(color: _AP.muted),
  ),
);
