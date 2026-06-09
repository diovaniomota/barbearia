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
      final rows = await Supabase.instance.client
          .from('plan_clients')
          .select()
          .order('name');
      if (!mounted) return;
      setState(() {
        _clients = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
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

    final rawPhone = client != null ? _displayPhone(client['phone'] ?? '') : '';
    final phoneCtrl = TextEditingController(text: rawPhone);
    final phoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####',
      filter: {'#': RegExp(r'[0-9]')},
      initialText: rawPhone,
    );

    String? selectedPayment = client?['payment_method']?.toString();

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
                  final data = {
                    'name': name,
                    'phone': phone,
                    'plan_name': planCtrl.text.trim().isEmpty
                        ? null
                        : planCtrl.text.trim(),
                    'payment_method': selectedPayment,
                    'due_day': dueDayRaw,
                    'notes': notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
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
                final dueDay = c['due_day'];
                final notes = c['notes']?.toString();
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.card_membership,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      c['name']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(_displayPhone(c['phone'] ?? '')),
                        if (planName != null && planName.isNotEmpty) ...[
                          const SizedBox(height: 4),
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
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                        if (paymentMethod != null && paymentMethod.isNotEmpty ||
                            dueDay != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (paymentMethod != null &&
                                  paymentMethod.isNotEmpty) ...[
                                const Icon(Icons.payment_outlined, size: 13),
                                const SizedBox(width: 4),
                                Text(
                                  paymentMethod,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                              if (paymentMethod != null &&
                                  paymentMethod.isNotEmpty &&
                                  dueDay != null)
                                const Text(
                                  '  ·  ',
                                  style: TextStyle(fontSize: 12),
                                ),
                              if (dueDay != null) ...[
                                const Icon(Icons.event_outlined, size: 13),
                                const SizedBox(width: 4),
                                Text(
                                  'Vence dia $dueDay',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                        if (notes != null && notes.isNotEmpty) ...[
                          const SizedBox(height: 2),
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
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Editar',
                          onPressed: () => _openDialog(client: c),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          tooltip: 'Remover',
                          onPressed: () => _delete(c),
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
