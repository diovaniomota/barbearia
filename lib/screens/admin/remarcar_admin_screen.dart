import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/services/whatsapp_service.dart';

class RemarcarAdminScreen extends StatefulWidget {
  const RemarcarAdminScreen({super.key});

  @override
  State<RemarcarAdminScreen> createState() => _RemarcarAdminScreenState();
}

class _RemarcarAdminScreenState extends State<RemarcarAdminScreen> {
  bool _loading = true;
  String? _error;
  List<_ClienteInativo> _clientes = [];
  WhatsappConfig _config = WhatsappConfig.empty();
  final Set<String> _sending = {};

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
      final config = await WhatsappService.loadConfig();
      final supabase = Supabase.instance.client;
      final cutoff = DateTime.now().subtract(const Duration(days: 30));

      // 1. Busca todos os agendamentos passados não cancelados
      final rows = await supabase
          .from('appointments')
          .select('customer_phone, customer_name, appointment_date, user_id, users:user_id(name, phone)')
          .lte('appointment_date', DateFormat('yyyy-MM-dd').format(DateTime.now()))
          .not('status', 'in', '("cancelled","canceled","no_show")')
          .order('appointment_date', ascending: false);

      // 2. Busca phones que têm agendamento futuro (não devem aparecer)
      final futureRows = await supabase
          .from('appointments')
          .select('customer_phone')
          .gt('appointment_date', DateFormat('yyyy-MM-dd').format(DateTime.now()))
          .not('status', 'in', '("cancelled","canceled","no_show")');

      final futurePhones = <String>{
        for (final r in (futureRows as List))
          _norm(r['customer_phone']?.toString() ?? ''),
      }..remove('');

      // 3. Agrupa por phone, pega última visita
      final byPhone = <String, _ClienteInativo>{};
      for (final r in (rows as List)) {
        String phone = _norm(r['customer_phone']?.toString() ?? '');
        String name  = (r['customer_name']?.toString() ?? '').trim();

        // Fallback para dados do user autenticado
        if (phone.isEmpty || name.isEmpty) {
          final usr = r['users'];
          if (usr is Map) {
            phone = phone.isNotEmpty ? phone : _norm(usr['phone']?.toString() ?? '');
            name  = name.isNotEmpty  ? name  : (usr['name']?.toString() ?? '').trim();
          }
        }
        if (phone.isEmpty) continue;

        final dateStr = r['appointment_date']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;

        // Atualiza com a data mais recente
        final existing = byPhone[phone];
        if (existing == null || date.isAfter(existing.ultimaVisita)) {
          byPhone[phone] = _ClienteInativo(
            nome: name.isEmpty ? 'Cliente' : name,
            phone: phone,
            ultimaVisita: date,
          );
        }
      }

      // 4. Filtra: só os que a última visita foi há mais de 30 dias
      //    e que não têm agendamento futuro
      final inativos = byPhone.values
          .where((c) =>
              c.ultimaVisita.isBefore(cutoff) &&
              !futurePhones.contains(c.phone))
          .toList()
        ..sort((a, b) => a.ultimaVisita.compareTo(b.ultimaVisita));

      if (!mounted) return;
      setState(() {
        _clientes = inativos;
        _config = config;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _norm(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

  String _displayPhone(String digits) {
    if (digits.length == 11) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return digits;
  }

  String _diasAusente(DateTime ultima) {
    final diff = DateTime.now().difference(ultima).inDays;
    return '$diff dias';
  }

  Future<void> _enviar(_ClienteInativo c) async {
    if (!_config.enabled || !_config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp não configurado. Acesse as configurações de WhatsApp.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _sending.add(c.phone));

    final dias = DateTime.now().difference(c.ultimaVisita).inDays;
    final msg =
        'Olá ${c.nome}! 👋\n\n'
        'Já faz $dias dias desde sua última visita à barbearia. '
        'Tá na hora de dar uma chegada! ✂️💈\n\n'
        'Agende seu horário e venha se cuidar!';

    final result = await WhatsappService.sendMessage(
      phone: c.phone,
      message: msg,
      config: _config,
    );

    if (!mounted) return;
    setState(() => _sending.remove(c.phone));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.ok
            ? 'Mensagem enviada para ${c.nome}!'
            : 'Erro: ${result.error}'),
        backgroundColor: result.ok ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _enviarTodos() async {
    final pendentes = _clientes.where((c) => !_sending.contains(c.phone)).toList();
    if (pendentes.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar para todos?'),
        content: Text(
          'Enviar mensagem de retorno para ${pendentes.length} cliente(s) inativo(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar todos'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final c in pendentes) {
      await _enviar(c);
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remarcar Clientes'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
          if (_clientes.isNotEmpty)
            IconButton(
              onPressed: _loading ? null : _enviarTodos,
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Enviar para todos',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 12),
                        Text('Erro ao carregar: $_error',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : _clientes.isEmpty
                  ? _EmptyState()
                  : Column(
                      children: [
                        _Banner(
                          count: _clientes.length,
                          wppOk: _config.enabled && _config.isConfigured,
                          theme: theme,
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                            itemCount: _clientes.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final c = _clientes[i];
                              final isSending = _sending.contains(c.phone);
                              final dias = DateTime.now()
                                  .difference(c.ultimaVisita)
                                  .inDays;
                              final urgente = dias >= 60;
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      // Avatar
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: urgente
                                            ? theme.colorScheme.error
                                                .withValues(alpha: 0.15)
                                            : theme.colorScheme.primary
                                                .withValues(alpha: 0.12),
                                        child: Text(
                                          c.nome.isNotEmpty
                                              ? c.nome[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: urgente
                                                ? theme.colorScheme.error
                                                : theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              c.nome,
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _displayPhone(c.phone),
                                              style: theme.textTheme.bodySmall,
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.schedule_rounded,
                                                  size: 12,
                                                  color: urgente
                                                      ? theme.colorScheme.error
                                                      : theme
                                                          .colorScheme.outline,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Ausente há ${_diasAusente(c.ultimaVisita)}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: urgente
                                                        ? theme
                                                            .colorScheme.error
                                                        : theme
                                                            .colorScheme.outline,
                                                    fontWeight: urgente
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Última: ${DateFormat('dd/MM/yy').format(c.ultimaVisita)}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: theme
                                                        .colorScheme.outline,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Botão enviar
                                      isSending
                                          ? const SizedBox(
                                              width: 36,
                                              height: 36,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          : FilledButton.icon(
                                              onPressed: () => _enviar(c),
                                              style: FilledButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8),
                                                textStyle: const TextStyle(
                                                    fontSize: 12),
                                              ),
                                              icon: const Icon(
                                                  Icons.send_rounded,
                                                  size: 14),
                                              label: const Text('Enviar'),
                                            ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}

// ── Modelos ───────────────────────────────────────────────────────────────────

class _ClienteInativo {
  final String nome;
  final String phone;
  final DateTime ultimaVisita;

  const _ClienteInativo({
    required this.nome,
    required this.phone,
    required this.ultimaVisita,
  });
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({
    required this.count,
    required this.wppOk,
    required this.theme,
  });

  final int count;
  final bool wppOk;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.person_off_outlined,
              color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count cliente(s) sem visita há mais de 30 dias',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (!wppOk)
            Tooltip(
              message: 'WhatsApp não configurado',
              child: Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 18),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Todos os clientes visitaram\nnos últimos 30 dias!',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Nenhum cliente inativo encontrado.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
