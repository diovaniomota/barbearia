import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:barbearia/utils/whatsapp_launcher.dart';

/// Cliente sem agendar há mais de 30 dias (candidato a reativação).
class InactiveClient {
  final String name;
  final String phone;
  final DateTime lastVisit;
  const InactiveClient({
    required this.name,
    required this.phone,
    required this.lastVisit,
  });
}

/// Linha de um cliente inativo: nome, última visita e botão de WhatsApp.
class InactiveClientTile extends StatelessWidget {
  final InactiveClient client;
  const InactiveClientTile({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = DateTime.now().difference(client.lastVisit).inDays;
    final lastLabel = DateFormat('dd/MM/yyyy').format(client.lastVisit);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Última vez: $lastLabel • há $days dias',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => openWhatsAppReactivation(
              context,
              phone: client.phone,
              name: client.name,
            ),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 20,
                color: Color(0xFF25D366),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tela com a lista completa de clientes a reativar.
class InactiveClientsScreen extends StatelessWidget {
  final List<InactiveClient> clients;
  const InactiveClientsScreen({super.key, required this.clients});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes para reativar')),
      body: clients.isEmpty
          ? Center(
              child: Text(
                'Nenhum cliente nessa situação.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: clients.length,
              separatorBuilder: (_, __) => Divider(
                color: theme.colorScheme.outline.withValues(alpha: 0.15),
                height: 1,
              ),
              itemBuilder: (_, i) => InactiveClientTile(client: clients[i]),
            ),
    );
  }
}
