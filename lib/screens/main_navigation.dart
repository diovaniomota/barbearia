import 'package:flutter/material.dart';
import 'package:barbearia/screens/home_screen.dart';
import 'package:barbearia/screens/appointments_screen.dart';
import 'package:barbearia/screens/services_screen.dart';
import 'package:barbearia/screens/profile_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({
    super.key,
    this.initialIndex = 0,
    this.showSchedule = true,
    this.showProfile = true,
  });
  final int initialIndex;
  final bool showSchedule;
  final bool showProfile;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int _currentIndex;
  late List<_NavItem> _items;
  @override
  void initState() {
    super.initState();
    _items = _buildItems();
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
  }

  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _items.map((e) => e.screen).toList(),
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
          backgroundColor: const Color.fromARGB(0, 34, 8, 180),
          elevation: 0,
          destinations: _items
              .map(
                (e) => NavigationDestination(
                  icon: Icon(e.icon, color: theme.colorScheme.onSurface),
                  selectedIcon: Icon(
                    e.selectedIcon,
                    color: theme.colorScheme.primary,
                  ),
                  label: e.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
  _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });
}

List<_NavItem> _baseItems() => [
  _NavItem(
    label: 'Início',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    screen: const HomeScreen(),
  ),
  _NavItem(
    label: 'Serviços',
    icon: Icons.content_cut_outlined,
    selectedIcon: Icons.content_cut,
    screen: const ServicesScreen(),
  ),
  _NavItem(
    label: 'Agendar',
    icon: Icons.calendar_today_outlined,
    selectedIcon: Icons.calendar_today,
    screen: const AppointmentsScreen(),
  ),
  _NavItem(
    label: 'Perfil',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    screen: const ProfileScreen(),
  ),
];

List<_NavItem> _filterItems({
  required bool showSchedule,
  required bool showProfile,
}) {
  final items = _baseItems();
  return items.where((i) {
    if (i.label == 'Agendar' && !showSchedule) return false;
    if (i.label == 'Perfil' && !showProfile) return false;
    return true;
  }).toList();
}

extension on _MainNavigationState {
  List<_NavItem> _buildItems() {
    return _filterItems(
      showSchedule: widget.showSchedule,
      showProfile: widget.showProfile,
    );
  }
}
