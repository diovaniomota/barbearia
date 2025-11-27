import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  int _users = 0;
  int _barbers = 0;
  int _services = 0;
  int _appointments = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final usersRows = await supabase.from('users').select('id');
      final barbersRows = await supabase.from('barbers').select('id');
      final servicesRows = await supabase.from('services').select('id');
      final appointmentsRows = await supabase.from('appointments').select('id');

      setState(() {
        _users = (usersRows as List).length;
        _barbers = (barbersRows as List).length;
        _services = (servicesRows as List).length;
        _appointments = (appointmentsRows as List).length;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')), 
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Erro: $_error'))
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _StatCard(title: 'Usuários', value: _users.toString(), icon: Icons.people),
                      const SizedBox(height: 12),
                      _StatCard(title: 'Barbeiros', value: _barbers.toString(), icon: Icons.person),
                      const SizedBox(height: 12),
                      _StatCard(title: 'Serviços', value: _services.toString(), icon: Icons.content_cut),
                      const SizedBox(height: 12),
                      _StatCard(title: 'Agendamentos', value: _appointments.toString(), icon: Icons.calendar_today),
                    ],
                  ),
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

