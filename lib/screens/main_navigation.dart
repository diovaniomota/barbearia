import 'package:flutter/material.dart';
import 'package:barbearia/screens/home_screen.dart';
import 'package:barbearia/screens/appointments_screen.dart';
import 'package:barbearia/screens/services_screen.dart';
import 'package:barbearia/screens/profile_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  // ORDEM DEVE BATER COM OS DESTINATIONS: Início, Serviços, Agendamentos, Perfil
  final List<Widget> _screens = [
    const HomeScreen(),
    const ServicesScreen(),
    const AppointmentsScreen(),
    const ProfileScreen(),
  ];
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          destinations: [
            NavigationDestination(
              icon:
                  Icon(Icons.home_outlined, color: theme.colorScheme.onSurface),
              selectedIcon: Icon(Icons.home, color: theme.colorScheme.primary),
              label: 'Início',
            ),
            NavigationDestination(
              icon: Icon(Icons.content_cut_outlined,
                  color: theme.colorScheme.onSurface),
              selectedIcon:
                  Icon(Icons.content_cut, color: theme.colorScheme.primary),
              label: 'Serviços',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined,
                  color: theme.colorScheme.onSurface),
              selectedIcon:
                  Icon(Icons.calendar_today, color: theme.colorScheme.primary),
              label: 'Agendamentos',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline,
                  color: theme.colorScheme.onSurface),
              selectedIcon:
                  Icon(Icons.person, color: theme.colorScheme.primary),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}