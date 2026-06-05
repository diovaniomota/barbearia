import 'package:flutter/material.dart';
import 'package:barbearia/screens/admin/dashboard_screen.dart';
import 'package:barbearia/screens/admin/services_admin_screen.dart';
import 'package:barbearia/screens/admin/barbers_admin_screen.dart';
import 'package:barbearia/screens/admin/appointments_admin_screen.dart';
import 'package:barbearia/screens/admin/financial_admin_screen.dart';
import 'package:barbearia/screens/admin/whatsapp_admin_screen.dart';
import 'package:barbearia/screens/admin/plan_clients_admin_screen.dart';

class AdminNavigation extends StatefulWidget {
  const AdminNavigation({super.key});

  @override
  State<AdminNavigation> createState() => _AdminNavigationState();
}

class _AdminNavigationState extends State<AdminNavigation> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;

  static const _screens = [
    DashboardScreen(),
    AppointmentsAdminScreen(),
    FinancialAdminScreen(),
    WhatsappAdminScreen(),
  ];

  static const _titles = ['Dashboard', 'Agenda', 'Caixa', 'WhatsApp'];

  void _navTo(int index) {
    Navigator.pop(context);
    setState(() => _currentIndex = index);
  }

  void _pushScreen(Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(theme),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            if (index == 4) {
              _scaffoldKey.currentState?.openDrawer();
              return;
            }
            setState(() => _currentIndex = index);
          },
          backgroundColor: const Color.fromARGB(0, 34, 8, 180),
          elevation: 0,
          indicatorColor: theme.colorScheme.primaryContainer,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined,
                  color: theme.colorScheme.onSurface),
              selectedIcon: Icon(Icons.dashboard,
                  color: theme.colorScheme.onPrimaryContainer),
              label: 'Dash',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined,
                  color: theme.colorScheme.onSurface),
              selectedIcon: Icon(Icons.calendar_today,
                  color: theme.colorScheme.onPrimaryContainer),
              label: 'Agenda',
            ),
            NavigationDestination(
              icon: Icon(Icons.attach_money_outlined,
                  color: theme.colorScheme.onSurface),
              selectedIcon: Icon(Icons.attach_money,
                  color: theme.colorScheme.onPrimaryContainer),
              label: 'Caixa',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded,
                  color: theme.colorScheme.onSurface),
              selectedIcon: Icon(Icons.chat_bubble_rounded,
                  color: theme.colorScheme.onPrimaryContainer),
              label: 'WhatsApp',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_rounded,
                  color: theme.colorScheme.onSurface),
              selectedIcon: Icon(Icons.menu_rounded,
                  color: theme.colorScheme.onSurface),
              label: 'Menu',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              color: theme.colorScheme.primaryContainer,
              child: Row(
                children: [
                  Icon(Icons.content_cut,
                      color: theme.colorScheme.onPrimaryContainer, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Barbearia Admin',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _DrawerSection(label: 'Principal'),
            _DrawerItem(
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              selected: _currentIndex == 0,
              onTap: () => _navTo(0),
            ),
            _DrawerItem(
              icon: Icons.calendar_today_outlined,
              label: 'Agenda',
              selected: _currentIndex == 1,
              onTap: () => _navTo(1),
            ),
            _DrawerItem(
              icon: Icons.attach_money_outlined,
              label: 'Caixa',
              selected: _currentIndex == 2,
              onTap: () => _navTo(2),
            ),
            _DrawerItem(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'WhatsApp',
              selected: _currentIndex == 3,
              onTap: () => _navTo(3),
            ),
            const Divider(indent: 16, endIndent: 16),
            _DrawerSection(label: 'Gerenciar'),
            _DrawerItem(
              icon: Icons.content_cut_outlined,
              label: 'Serviços',
              onTap: () => _pushScreen(const ServicesAdminScreen()),
            ),
            _DrawerItem(
              icon: Icons.person_outline,
              label: 'Barbeiros',
              onTap: () => _pushScreen(const BarbersAdminScreen()),
            ),
            _DrawerItem(
              icon: Icons.card_membership_outlined,
              label: 'Clientes Plano',
              onTap: () => _pushScreen(const PlanClientsAdminScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      onTap: onTap,
    );
  }
}
