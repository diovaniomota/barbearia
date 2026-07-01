import 'package:barbearia/screens/admin/recurring_schedule_screen.dart';
import 'package:barbearia/utils/admin_session.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class PlanClientsAdminScreen extends StatefulWidget {
  const PlanClientsAdminScreen({super.key});

  @override
  State<PlanClientsAdminScreen> createState() => _PlanClientsAdminScreenState();
}

class _PlanClientsAdminScreenState extends State<PlanClientsAdminScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _clients = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      List<Map<String, dynamic>> rows;

      if (AdminSession.isBarber) {
        rows = List<Map<String, dynamic>>.from(
          await client
              .from('plan_clients')
              .select()
              .eq('barber_id', AdminSession.barberId!)
              .order('name'),
        );
      } else {
        rows = List<Map<String, dynamic>>.from(
          await client.from('plan_clients').select().order('name'),
        );
      }

      if (!mounted) return;
      setState(() {
        _clients = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar: $e')),
      );
    }
  }

  String _normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');

  String _displayPhone(String phone) {
    final d = _normalizePhone(phone);
    if (d.length == 11) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
    }
    if (d.length == 10) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }
    return phone;
  }

  static const _paymentOptions = [
    'PIX',
    'Dinheiro',
    'Cartão de crédito',
    'Cartão de débito',
    'Outro',
  ];

  Future<void> _openDialog({Map<String, dynamic>? client}) async {
    final isEdit = client != null;
    final nameCtrl = TextEditingController(text: client?['name'] ?? '');
    final planCtrl = TextEditingController(text: client?['plan_name'] ?? '');
    final notesCtrl = TextEditingController(text: client?['notes'] ?? '');
    final dueDayCtrl = TextEditingController(
      text: client?['due_day']?.toString() ?? '',
    );
    final monthlyValueCtrl = TextEditingController(
      text: client?['monthly_value'] != null
          ? (client!['monthly_value'] as num).toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    final pixKeyCtrl = TextEditingController(text: client?['pix_key'] ?? '');

    final rawPhone = client != null ? _displayPhone(client['phone'] ?? '') : '';
    final phoneCtrl = TextEditingController(text: rawPhone);
    final phoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####',
      filter: {'#': RegExp(r'[0-9]')},
      initialText: rawPhone,
    );

    String? selectedPayment = client?['payment_method']?.toString();
    String? selectedBarberId = client?['barber_id']?.toString()
        ?? (AdminSession.isBarber ? AdminSession.barberId : null);

    // Super-admin: carregar lista de barbeiros para o seletor
    List<Map<String, dynamic>> allBarbers = [];
    if (AdminSession.isSuperAdmin) {
      final rows = await Supabase.instance.client
          .from('barbers')
          .select('id,name')
          .order('name');
      allBarbers = List<Map<String, dynamic>>.from(rows);
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(isEdit ? 'Editar cliente plano' : 'Novo cliente plano'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo *',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [phoneMask],
                  decoration: const InputDecoration(
                    labelText: 'Telefone *',
                    hintText: '(00) 00000-0000',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: planCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do plano',
                    hintText: 'Ex: Mensal, Quinzenal...',
                    prefixIcon: Icon(Icons.card_membership_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: monthlyValueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Valor da mensalidade',
                    hintText: '0,00',
                    prefixIcon: Icon(Icons.attach_money_outlined),
                    prefixText: 'R\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedPayment,
                  decoration: const InputDecoration(
                    labelText: 'Forma de pagamento',
                    prefixIcon: Icon(Icons.payment_outlined),
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Selecionar...'),
                  items: _paymentOptions
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => selectedPayment = v),
                ),
                if (selectedPayment == 'PIX') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: pixKeyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Chave Pix a enviar para este cliente',
                      hintText: 'CPF, e-mail, telefone ou chave aleatória',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: dueDayCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dia de vencimento',
                    hintText: '1 – 31',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observações',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                if (AdminSession.isSuperAdmin) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedBarberId,
                    decoration: const InputDecoration(
                      labelText: 'Barbeiro responsável',
                      prefixIcon: Icon(Icons.content_cut_outlined),
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Sem vínculo'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sem vínculo')),
                      ...allBarbers.map(
                        (b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['name'].toString())),
                      ),
                    ],
                    onChanged: (v) => setStateDialog(() => selectedBarberId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final phone = _normalizePhone(phoneCtrl.text);
                if (name.isEmpty || phone.length < 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nome e telefone são obrigatórios.'),
                    ),
                  );
                  return;
                }
                final dueDayRaw = int.tryParse(dueDayCtrl.text.trim());
                if (dueDayRaw != null && (dueDayRaw < 1 || dueDayRaw > 31)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dia de vencimento deve ser entre 1 e 31.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
                try {
                  final monthlyValueRaw = double.tryParse(
                    monthlyValueCtrl.text.trim().replaceAll(',', '.'),
                  );
                  final data = {
                    'name': name,
                    'phone': phone,
                    'plan_name': planCtrl.text.trim().isEmpty
                        ? null
                        : planCtrl.text.trim(),
                    'monthly_value': monthlyValueRaw,
                    'payment_method': selectedPayment,
                    'pix_key': selectedPayment == 'PIX' && pixKeyCtrl.text.trim().isNotEmpty
                        ? pixKeyCtrl.text.trim()
                        : null,
                    'due_day': dueDayRaw,
                    'notes': notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                    'barber_id': selectedBarberId,
                    'updated_at': DateTime.now().toIso8601String(),
                  };
                  if (isEdit) {
                    await Supabase.instance.client
                        .from('plan_clients')
                        .update(data)
                        .eq('id', client['id']);
                  } else {
                    await Supabase.instance.client
                        .from('plan_clients')
                        .insert(data);
                  }
                  await _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Erro: $e')));
                  }
                }
              },
              child: Text(isEdit ? 'Salvar' : 'Adicionar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover do plano'),
        content: Text(
          'Remover "${client['name']}" da lista de clientes plano?\n\nAgendamentos já realizados não serão alterados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client
          .from('plan_clients')
          .delete()
          .eq('id', client['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes Plano'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDialog(),
        tooltip: 'Adicionar cliente plano',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _clients.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.card_membership_outlined,
                    size: 72,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum cliente plano cadastrado',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toque em + para adicionar',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _clients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = _clients[i];
                final planName = c['plan_name']?.toString();
                final paymentMethod = c['payment_method']?.toString();
                final pixKey = c['pix_key']?.toString();
                final dueDay = c['due_day'];
                final notes = c['notes']?.toString();
                final monthlyValue = c['monthly_value'] != null
                    ? (c['monthly_value'] as num).toDouble()
                    : null;
                final hasPayment =
                    paymentMethod != null && paymentMethod.isNotEmpty;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(
                            Icons.card_membership,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Conteúdo flexível — ocupa o espaço restante e trunca
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c['name']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _displayPhone(c['phone'] ?? ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (planName != null && planName.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    planName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                              if (monthlyValue != null || hasPayment || dueDay != null) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (monthlyValue != null)
                                      _InfoChip(
                                        icon: Icons.attach_money_outlined,
                                        label: 'R\$ ${monthlyValue.toStringAsFixed(2).replaceAll('.', ',')}',
                                        color: theme.colorScheme.primary,
                                      ),
                                    if (hasPayment)
                                      _InfoChip(
                                        icon: Icons.payment_outlined,
                                        label: paymentMethod,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    if (paymentMethod == 'PIX' &&
                                        pixKey != null &&
                                        pixKey.isNotEmpty)
                                      _InfoChip(
                                        icon: Icons.key_outlined,
                                        label: pixKey,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    if (dueDay != null)
                                      _InfoChip(
                                        icon: Icons.event_outlined,
                                        label: 'Vence dia $dueDay',
                                        color: theme.colorScheme.onSurface,
                                      ),
                                  ],
                                ),
                              ],
                              if (notes != null && notes.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  notes,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Ações compactas — recorrente visível + menu
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.repeat_rounded,
                                color: theme.colorScheme.primary,
                              ),
                              tooltip: 'Agendamentos recorrentes',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                // Repassa o tema admin para a tela empilhada,
                                // senão ela abre com o tema claro padrão.
                                final adminTheme = Theme.of(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Theme(
                                      data: adminTheme,
                                      child: RecurringScheduleScreen(
                                        planClientId: c['id'].toString(),
                                        planClientName:
                                            c['name']?.toString() ?? '',
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              tooltip: 'Mais opções',
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _openDialog(client: c);
                                } else if (v == 'delete') {
                                  _delete(c);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 20),
                                      SizedBox(width: 12),
                                      Text('Editar'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                        color: theme.colorScheme.error,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Remover',
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// Pequeno rótulo com ícone — usado nas infos de pagamento/vencimento.
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }
}
