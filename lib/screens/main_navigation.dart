import 'package:barbearia/screens/appointments_screen.dart';
import 'package:barbearia/screens/customer_history_screen.dart';
import 'package:barbearia/screens/home_screen.dart';
import 'package:barbearia/screens/profile_screen.dart';
import 'package:barbearia/screens/services_screen.dart';
import 'package:flutter/material.dart';

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
  late List<bool> _builtTabs;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    _builtTabs = List<bool>.filled(_items.length, false);
    _builtTabs[_currentIndex] = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_items.length, (index) {
          if (!_builtTabs[index]) return const SizedBox.shrink();
          return _items[index].screen;
        }),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: _NavPalette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: _NavPalette.gold.withValues(alpha: 0.75),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              indicatorColor: _NavPalette.gold.withValues(alpha: 0.14),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return theme.textTheme.labelSmall?.copyWith(
                  color: selected ? _NavPalette.gold : _NavPalette.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                );
              }),
            ),
            child: NavigationBar(
              height: 72,
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _builtTabs[index] = true;
                  _currentIndex = index;
                });
              },
              backgroundColor: Colors.transparent,
              elevation: 0,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: _items
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon, color: _NavPalette.muted),
                      selectedIcon: Icon(
                        item.selectedIcon,
                        color: _NavPalette.gold,
                      ),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

class _NavPalette {
  static const Color background = Color(0xFF0D0909);
  static const Color gold = Color(0xFFFFD400);
  static const Color muted = Color(0xFF8F7B53);
}

List<_NavItem> _baseItems() => const [
  _NavItem(
    label: 'Inicio',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    screen: HomeScreen(),
  ),
  _NavItem(
    label: 'Servicos',
    icon: Icons.content_cut_outlined,
    selectedIcon: Icons.content_cut,
    screen: ServicesScreen(),
  ),
  _NavItem(
    label: 'Agendar',
    icon: Icons.calendar_today_outlined,
    selectedIcon: Icons.calendar_today,
    screen: AppointmentsScreen(),
  ),
  _NavItem(
    label: 'Perfil',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    screen: ProfileScreen(),
  ),
];

List<_NavItem> _filterItems({
  required bool showSchedule,
  required bool showProfile,
}) {
  if (!showSchedule && !showProfile) {
    return const [
      _NavItem(
        label: 'Agendar',
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        screen: HomeScreen(),
      ),
      _NavItem(
        label: 'Hist\u00F3rico',
        icon: Icons.history_outlined,
        selectedIcon: Icons.history,
        screen: CustomerHistoryScreen(),
      ),
    ];
  }

  final items = _baseItems();
  return items.where((item) {
    if (item.label == 'Agendar' && !showSchedule) return false;
    if (item.label == 'Perfil' && !showProfile) return false;
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
