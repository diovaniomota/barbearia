// lib/screens/appointments_screen.dart

import 'package:barbearia/widgets/appointment_card.dart';
import 'package:flutter/material.dart';
import 'package:barbearia/models/appointment.dart';
import 'package:barbearia/screens/book_appointment_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Agendamentos'),
        actions: [
          IconButton(
            tooltip: 'Novo agendamento',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BookAppointmentScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelStyle: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(text: 'Próximos'),
            Tab(text: 'Histórico'),
            Tab(text: 'Cancelados'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _AppointmentsList(
            status: [AppointmentStatus.pending, AppointmentStatus.confirmed],
          ),
          _AppointmentsList(status: [AppointmentStatus.completed]),
          _AppointmentsList(status: [AppointmentStatus.cancelled]),
        ],
      ),
    );
  }
}

class _AppointmentsList extends StatefulWidget {
  const _AppointmentsList({required this.status});
  final List<AppointmentStatus> status;

  @override
  State<_AppointmentsList> createState() => _AppointmentsListState();
}

class _AppointmentsListState extends State<_AppointmentsList> {
  late Future<List<Appointment>> _appointmentsFuture;

  @override
  void initState() {
    super.initState();
    _appointmentsFuture = Appointment.fetchAppointmentsForCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Appointment>>(
      future: _appointmentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }

        final allAppointments = snapshot.data ?? [];
        final filteredAppointments = allAppointments
            .where((appt) => widget.status.contains(appt.status))
            .toList();

        if (filteredAppointments.isEmpty) {
          return const Center(child: Text('Nenhum agendamento encontrado.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredAppointments.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 14.0),
            child: AppointmentCard(appointment: filteredAppointments[i]),
          ),
        );
      },
    );
  }
}
