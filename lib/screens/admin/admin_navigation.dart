import 'package:flutter/material.dart';
import 'package:barbearia/screens/admin/dashboard_screen.dart';
import 'package:barbearia/screens/admin/services_admin_screen.dart';
import 'package:barbearia/screens/admin/barbers_admin_screen.dart';
import 'package:barbearia/screens/admin/appointments_admin_screen.dart';
import 'package:barbearia/screens/admin/financial_admin_screen.dart';
import 'package:barbearia/screens/admin/whatsapp_admin_screen.dart';

class AdminNavigation extends StatefulWidget {
  const AdminNavigation({super.key});

  @override
  State<AdminNavigation> createState() => _AdminNavigationState();
}

class _AdminNavigationState extends State<AdminNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    ServicesAdminScreen(),
    BarbersAdminScreen(),
    AppointmentsAdminScreen(),
    FinancialAdminScreen(),
    WhatsappAdminScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
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
          onDestinationSelected: (index) =>
              setState(() => _currentIndex = index),
          backgroundColor: const Color.fromARGB(0, 34, 8, 180),
          elevation: 0,
          indicatorColor: theme.colorScheme.primaryContainer,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: [
            NavigationDestination(
              icon: Icon(
                Icons.dashboard_outlined,
                color: theme.colorScheme.onSurface,
              ),
              selectedIcon: Icon(
                Icons.dashboard,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              label: 'Dash',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.content_cut_outlined,
                color: theme.colorScheme.onSurface,
              ),
              selectedIcon: Icon(
                Icons.content_cut,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              label: 'Serviços',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.person_outline,
                color: theme.colorScheme.onSurface,
              ),
              selectedIcon: Icon(
                Icons.person,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              label: 'Barbeiros',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.calendar_today_outlined,
                color: theme.colorScheme.onSurface,
              ),
              selectedIcon: Icon(
                Icons.calendar_today,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              label: 'Agenda',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.attach_money_outlined,
                color: theme.colorScheme.onSurface,
              ),
              selectedIcon: Icon(
                Icons.attach_money,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              label: 'Caixa',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.chat_bubble_outline_rounded,
                color: theme.colorScheme.onSurface,
              ),
              selectedIcon: Icon(
                Icons.chat_bubble_rounded,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              label: 'WhatsApp',
            ),
          ],
        ),
      ),
    );
  }
}
