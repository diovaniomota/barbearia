// lib/screens/appointments_screen.dart

import 'package:barbearia/widgets/appointment_card.dart';
import 'package:flutter/material.dart';
import 'package:barbearia/models/appointment.dart';
import 'package:barbearia/screens/book_appointment_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  List<Map<String, dynamic>> appointments = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    try {
      final response = await Supabase.instance.client
          .from('appointments')
          .select('''
            *,
            users:user_id(name, email),
            barbers:barber_id(name),
            services:service_id(name, price)
          ''')
          .order(
            'scheduled_at',
            ascending: false,
          ); // CORRIGIDO: appointment_date → scheduled_at

      setState(() {
        appointments = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar agendamentos: $error')),
        );
      }
    }
  }

  Future<void> _refreshAppointments() async {
    setState(() {
      isLoading = true;
    });
    await _loadAppointments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Agendamentos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _refreshAppointments,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Novo agendamento',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BookAppointmentScreen(),
                ),
              ).then((_) => _refreshAppointments()); // Atualiza ao voltar
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(children: [Expanded(child: _buildAppointmentsList())]),
    );
  }

  Widget _buildAppointmentsList() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum agendamento encontrado',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Toque no + para criar seu primeiro agendamento',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAppointments,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: appointments.length,
        itemBuilder: (context, index) {
          final appointment = appointments[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _AppointmentCard(appointment: appointment),
          );
        },
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appointment;

  const _AppointmentCard({required this.appointment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Dados do agendamento com verificações de segurança
    DateTime appointmentDate;
    try {
      appointmentDate = DateTime.parse(
        appointment['scheduled_at'] ??
            DateTime.now()
                .toIso8601String(), // CORRIGIDO: appointment_date → scheduled_at
      );
    } catch (e) {
      appointmentDate = DateTime.now();
    }

    final userName =
        appointment['users']?['name'] ??
        (appointment['users'] != null &&
                appointment['users'] is List &&
                appointment['users'].isNotEmpty
            ? appointment['users'][0]['name']
            : 'Usuário não encontrado');

    final barberName =
        appointment['barbers']?['name'] ??
        (appointment['barbers'] != null &&
                appointment['barbers'] is List &&
                appointment['barbers'].isNotEmpty
            ? appointment['barbers'][0]['name']
            : 'Barbeiro não encontrado');

    final serviceName =
        appointment['services']?['name'] ??
        (appointment['services'] != null &&
                appointment['services'] is List &&
                appointment['services'].isNotEmpty
            ? appointment['services'][0]['name']
            : 'Serviço não encontrado');

    final servicePrice =
        appointment['services']?['price']?.toString() ??
        (appointment['services'] != null &&
                appointment['services'] is List &&
                appointment['services'].isNotEmpty
            ? appointment['services'][0]['price']?.toString()
            : '0');

    // Formatação da data
    final formattedDate =
        '${appointmentDate.day.toString().padLeft(2, '0')}/'
        '${appointmentDate.month.toString().padLeft(2, '0')}/'
        '${appointmentDate.year}';

    final formattedTime =
        '${appointmentDate.hour.toString().padLeft(2, '0')}:'
        '${appointmentDate.minute.toString().padLeft(2, '0')}';

    // Status do agendamento
    final status = appointment['status'] ?? 'pending';
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'confirmed':
        statusColor = Colors.green;
        statusText = 'Confirmado';
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusText = 'Cancelado';
        statusIcon = Icons.cancel;
        break;
      case 'completed':
        statusColor = Colors.blue;
        statusText = 'Concluído';
        statusIcon = Icons.done_all;
        break;
      default:
        statusColor = Colors.orange;
        statusText = 'Pendente';
        statusIcon = Icons.schedule;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header com status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  'ID: ${appointment['id'].toString().substring(0, 8)}...',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Informações principais
            Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  '$formattedDate às $formattedTime',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Icon(Icons.person, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text('Cliente: $userName', style: theme.textTheme.bodyMedium),
              ],
            ),

            const SizedBox(height: 4),

            Row(
              children: [
                Icon(Icons.cut, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Barbeiro: $barberName',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),

            const SizedBox(height: 4),

            Row(
              children: [
                Icon(Icons.content_cut, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Serviço: $serviceName',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  'R\$ $servicePrice',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            // Botões de ação (se necessário)
            if (status == 'pending') ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      // Implementar cancelamento
                      _showCancelDialog(context, appointment['id']);
                    },
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancelar'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Implementar confirmação
                      _confirmAppointment(context, appointment['id']);
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirmar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCancelDialog(BuildContext context, String appointmentId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Agendamento'),
        content: const Text(
          'Tem certeza que deseja cancelar este agendamento?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateAppointmentStatus(context, appointmentId, 'cancelled');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancelar Agendamento'),
          ),
        ],
      ),
    );
  }

  void _confirmAppointment(BuildContext context, String appointmentId) {
    _updateAppointmentStatus(context, appointmentId, 'confirmed');
  }

  Future<void> _updateAppointmentStatus(
    BuildContext context,
    String appointmentId,
    String newStatus,
  ) async {
    try {
      await Supabase.instance.client
          .from('appointments')
          .update({'status': newStatus})
          .eq('id', appointmentId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Agendamento ${newStatus == 'confirmed' ? 'confirmado' : 'cancelado'} com sucesso!',
            ),
            backgroundColor: newStatus == 'confirmed'
                ? Colors.green
                : Colors.orange,
          ),
        );

        // Trigger refresh da lista
        (context.findAncestorStateOfType<_AppointmentsScreenState>())
            ?._refreshAppointments();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar agendamento: $error')),
        );
      }
    }
  }
}
