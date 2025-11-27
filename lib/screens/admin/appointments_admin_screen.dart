import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppointmentsAdminScreen extends StatefulWidget {
  const AppointmentsAdminScreen({super.key});

  @override
  State<AppointmentsAdminScreen> createState() =>
      _AppointmentsAdminScreenState();
}

class _AppointmentsAdminScreenState extends State<AppointmentsAdminScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _appointments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('appointments')
          .select('''
            *,
            users:user_id(name, email),
            barbers:barber_id(name),
            services:service_id(name)
          ''')
          .order('created_at', ascending: false);
      setState(() {
        _appointments = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Status removido

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agendamentos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Erro: $_error'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _appointments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final a = _appointments[index];
                  final userName = a['users'] is Map
                      ? (a['users']['name']?.toString() ?? '')
                      : '';
                  final barberName = a['barbers'] is Map
                      ? (a['barbers']['name']?.toString() ?? '')
                      : '';
                  final serviceName = a['services'] is Map
                      ? (a['services']['name']?.toString() ?? '')
                      : '';
                  return ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text('$userName • $serviceName'),
                    subtitle: Text('Barbeiro: $barberName'),
                    // Status removido da visão/admin
                  );
                },
              ),
            ),
    );
  }
}
