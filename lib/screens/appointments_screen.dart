import 'package:flutter/material.dart';
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
                  builder: (_) => const BookAppointmentScreen(), // sem service
                ),
              );
            },
            icon: const Icon(Icons.add),
          )
        ],
        bottom: TabBar(
          controller: _tab,
          labelStyle:
              theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
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
          _AppointmentsList(kind: _ListKind.upcoming),
          _AppointmentsList(kind: _ListKind.history),
          _AppointmentsList(kind: _ListKind.cancelled),
        ],
      ),
    );
  }
}

enum _ListKind { upcoming, history, cancelled }

class _AppointmentsList extends StatelessWidget {
  const _AppointmentsList({required this.kind});
  final _ListKind kind;

  @override
  Widget build(BuildContext context) {
    // MOCKS — substitua por dados do Supabase
    final items = switch (kind) {
      _ListKind.upcoming => _mockUpcoming,
      _ListKind.history => _mockHistory,
      _ListKind.cancelled => _mockCancelled,
    };

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _AppointmentCard(data: items[i]),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status =
        data['status'] as String; // Confirmado / Pendente / Cancelado

    Color chipColor;
    switch (status) {
      case 'Confirmado':
        chipColor = Colors.green;
        break;
      case 'Pendente':
        chipColor = Colors.orange;
        break;
      default:
        chipColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // título + status
          Row(
            children: [
              Expanded(
                child: Text(
                  data['service'] as String,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: chipColor.withOpacity(.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: chipColor.withOpacity(.35)),
                ),
                child: Text(
                  status,
                  style:
                      theme.textTheme.labelMedium?.copyWith(color: chipColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // barbeiro / cliente
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.primary,
                child: Icon(Icons.person,
                    size: 18, color: theme.colorScheme.onPrimary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Barbeiro: ${data['barber']}',
                        style: theme.textTheme.bodyMedium),
                    Text('Cliente: ${data['client']}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // data • hora • preço
          Row(
            children: [
              _infoChip(context, icon: Icons.event, text: data['date']),
              const SizedBox(width: 8),
              _infoChip(context, icon: Icons.schedule, text: data['time']),
              const SizedBox(width: 8),
              _infoChip(context, icon: Icons.attach_money, text: data['price']),
            ],
          ),
          const SizedBox(height: 12),

          if ((data['notes'] as String).isNotEmpty) ...[
            Text('Observações:', style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Text(data['notes'] as String),
            ),
            const SizedBox(height: 12),
          ],

          // ações
          Row(
            children: [
              if (status != 'Cancelado')
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar'),
                  ),
                ),
              if (status != 'Cancelado') const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Reagendar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(BuildContext context,
      {required IconData icon, required String text}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Text(text, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ------------------ MOCKS p/ visualização ------------------

final _mockUpcoming = <Map<String, dynamic>>[
  {
    'service': 'Corte Tradicional',
    'status': 'Confirmado',
    'barber': 'João Silva',
    'client': 'Maria Silva',
    'date': '23/08/2025',
    'time': '18:45',
    'price': 'R\$ 25.00',
    'notes': 'Corte não muito curto',
  },
  {
    'service': 'Corte + Barba',
    'status': 'Pendente',
    'barber': 'Pedro Santos',
    'client': 'José Santos',
    'date': '24/08/2025',
    'time': '19:45',
    'price': 'R\$ 40.00',
    'notes': '',
  },
];

final _mockHistory = <Map<String, dynamic>>[
  {
    'service': 'Degradê',
    'status': 'Concluído',
    'barber': 'Carlos Oliveira',
    'client': 'João Pedro',
    'date': '19/08/2025',
    'time': '10:00',
    'price': 'R\$ 30.00',
    'notes': '',
  },
];

final _mockCancelled = <Map<String, dynamic>>[
  {
    'service': 'Barba',
    'status': 'Cancelado',
    'barber': 'Pedro Santos',
    'client': 'Luis',
    'date': '18/08/2025',
    'time': '14:30',
    'price': 'R\$ 20.00',
    'notes': 'Imprevisto',
  },
];
