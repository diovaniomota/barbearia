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
    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFF0C0D10),
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_items.length, (index) {
          if (!_builtTabs[index]) return const SizedBox.shrink();
          return _items[index].screen;
        }),
      ),
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: _currentIndex,
        items: _items,
        onTap: (index) {
          setState(() {
            _builtTabs[index] = true;
            _currentIndex = index;
          });
        },
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

// ── Floating pill navbar ──────────────────────────────────────────────────────

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final int currentIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF14161A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF252830)),
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
                final selected = i == currentIndex;
                final item = items[i];
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
                                ? const Color(0xFFF5C440).withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            selected ? item.selectedIcon : item.icon,
                            color: selected
                                ? const Color(0xFFF5C440)
                                : const Color(0xFF6B7280),
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: selected
                                ? const Color(0xFFF5C440)
                                : const Color(0xFF6B7280),
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
