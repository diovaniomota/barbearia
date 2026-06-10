import 'package:barbearia/utils/admin_session.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kDays = [
  'Domingo',
  'Segunda-feira',
  'Terça-feira',
  'Quarta-feira',
  'Quinta-feira',
  'Sexta-feira',
  'Sábado',
];

class RecurringScheduleScreen extends StatefulWidget {
  final String planClientId;
  final String planClientName;

  const RecurringScheduleScreen({
    super.key,
    required this.planClientId,
    required this.planClientName,
  });

  @override
  State<RecurringScheduleScreen> createState() =>
      _RecurringScheduleScreenState();
}

class _RecurringScheduleScreenState extends State<RecurringScheduleScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _barbers = [];
  List<Map<String, dynamic>> _services = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sb = Supabase.instance.client;

      // Recorrentes deste cliente — barbeiro vê apenas os seus
      var recQuery = sb
          .from('recurring_schedules')
          .select(
            'id,day_of_week,appointment_time,is_active,barber_id,'
            'barbers!barber_id(id,name),'
            'services!service_id(id,name,duration_blocks)',
          )
          .eq('plan_client_id', widget.planClientId);
      if (AdminSession.isBarber) {
        recQuery = recQuery.eq('barber_id', AdminSession.barberId!);
      }

      // Barbeiros para o seletor — barbeiro vê apenas a si mesmo
      var barbersQuery = sb.from('barbers').select('id,name');
      if (AdminSession.isBarber) {
        barbersQuery = barbersQuery.eq('id', AdminSession.barberId!);
      }

      final results = await Future.wait([
        recQuery.order('day_of_week').order('appointment_time'),
        barbersQuery.order('name'),
        sb.from('services').select('id,name,duration_blocks').order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        _schedules = List<Map<String, dynamic>>.from(results[0] as List);
        _barbers   = List<Map<String, dynamic>>.from(results[1] as List);
        _services  = List<Map<String, dynamic>>.from(results[2] as List);
        _loading   = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
    }
  }

  Future<void> _openDialog({Map<String, dynamic>? sched}) async {
    final isEdit = sched != null;

    int?      selDay       = isEdit ? sched['day_of_week'] as int? : null;
    TimeOfDay? selTime;
    if (isEdit) {
      final raw  = (sched['appointment_time'] as String? ?? '09:00');
      final parts = raw.split(':');
      selTime = TimeOfDay(
        hour:   int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }
    String? selBarberId = isEdit
        ? (sched['barbers']  is Map ? (sched['barbers']  as Map)['id']?.toString() : null)
        : (AdminSession.isBarber ? AdminSession.barberId : null);
    String? selServiceId = isEdit
        ? (sched['services'] is Map ? (sched['services'] as Map)['id']?.toString() : null)
        : null;
    bool    isActive     = isEdit ? (sched['is_active'] as bool? ?? true) : true;
    String? err;

    // Captura o tema atual (admin) para re-aplicar no dialog, que abre
    // no root navigator e não herda a subárvore de tema.
    final dialogTheme = Theme.of(context);

    await showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: dialogTheme,
        child: StatefulBuilder(
        builder: (ctx, setSt) {
          // Computed label — local variable, não getter
          final timeLabel = selTime == null
              ? 'Selecionar horário'
              : '${selTime!.hour.toString().padLeft(2, '0')}:'
                '${selTime!.minute.toString().padLeft(2, '0')}';

          Future<void> pickTime() async {
            final t = await showTimePicker(
              context: ctx,
              initialTime: selTime ?? const TimeOfDay(hour: 9, minute: 0),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: const TextScaler.linear(1.0)),
                child: child!,
              ),
            );
            if (t != null) setSt(() => selTime = t);
          }

          return AlertDialog(
            title: Text(
              isEdit ? 'Editar recorrente' : 'Novo agendamento recorrente',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dia da semana
                  DropdownButtonFormField<int>(
                    initialValue: selDay,
                    dropdownColor: Theme.of(ctx).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    decoration: const InputDecoration(
                      labelText: 'Dia da semana *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    hint: const Text('Selecionar…'),
                    items: List.generate(
                      7,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(_kDays[i]),
                      ),
                    ),
                    onChanged: (v) => setSt(() => selDay = v),
                  ),
                  const SizedBox(height: 12),

                  // Horário
                  OutlinedButton.icon(
                    onPressed: pickTime,
                    icon: const Icon(Icons.access_time_outlined),
                    label: Text(timeLabel),
                  ),
                  const SizedBox(height: 12),

                  // Barbeiro — barbeiro-admin fica fixo em si mesmo
                  if (AdminSession.isBarber)
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Barbeiro',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      child: Text(AdminSession.barberName ?? 'Você'),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: selBarberId,
                      dropdownColor: Theme.of(ctx).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Barbeiro *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      hint: const Text('Selecionar…'),
                      items: _barbers
                          .map(
                            (b) => DropdownMenuItem<String>(
                              value: b['id']?.toString(),
                              child: Text(b['name']?.toString() ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setSt(() => selBarberId = v),
                    ),
                  const SizedBox(height: 12),

                  // Serviço
                  DropdownButtonFormField<String>(
                    initialValue: selServiceId,
                    dropdownColor: Theme.of(ctx).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Serviço *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.content_cut_outlined),
                    ),
                    hint: const Text('Selecionar…'),
                    items: _services
                        .map(
                          (s) => DropdownMenuItem<String>(
                            value: s['id']?.toString(),
                            child: Text(s['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setSt(() => selServiceId = v),
                  ),
                  const SizedBox(height: 12),

                  // Ativo
                  SwitchListTile(
                    value: isActive,
                    onChanged: (v) => setSt(() => isActive = v),
                    title: const Text('Ativo'),
                    subtitle: const Text('Gera agendamentos automaticamente'),
                    contentPadding: EdgeInsets.zero,
                  ),

                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        err!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontSize: 12,
                        ),
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
                  if (selDay == null) {
                    setSt(() => err = 'Selecione o dia da semana.');
                    return;
                  }
                  if (selTime == null) {
                    setSt(() => err = 'Selecione o horário.');
                    return;
                  }
                  if (selBarberId == null) {
                    setSt(() => err = 'Selecione o barbeiro.');
                    return;
                  }
                  if (selServiceId == null) {
                    setSt(() => err = 'Selecione o serviço.');
                    return;
                  }
                  final h = selTime!.hour.toString().padLeft(2, '0');
                  final m = selTime!.minute.toString().padLeft(2, '0');
                  final data = {
                    'plan_client_id': widget.planClientId,
                    'barber_id':      selBarberId,
                    'service_id':     selServiceId,
                    'day_of_week':    selDay,
                    'appointment_time': '$h:$m:00',
                    'is_active':      isActive,
                    'updated_at': DateTime.now().toIso8601String(),
                  };
                  Navigator.pop(ctx);
                  try {
                    if (isEdit) {
                      await Supabase.instance.client
                          .from('recurring_schedules')
                          .update(data)
                          .eq('id', sched['id']);
                    } else {
                      await Supabase.instance.client
                          .from('recurring_schedules')
                          .insert(data);
                    }
                    await _load();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Erro: $e')));
                    }
                  }
                },
                child: Text(isEdit ? 'Salvar' : 'Criar'),
              ),
            ],
          );
        },
        ),
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> sched) async {
    final newVal = !(sched['is_active'] as bool? ?? true);
    try {
      await Supabase.instance.client
          .from('recurring_schedules')
          .update({
            'is_active':  newVal,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', sched['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> sched) async {
    final barberMap  = sched['barbers']  is Map ? sched['barbers']  as Map : {};
    final barberName = barberMap['name']?.toString() ?? '';
    final time       = (sched['appointment_time'] as String? ?? '').substring(0, 5);
    final day        = _kDays[sched['day_of_week'] as int? ?? 0];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: const Text('Excluir recorrente?'),
          content: Text(
            'Remover o agendamento de $day às $time com $barberName?\n\n'
            'Os horários futuros já reservados por esta recorrência serão '
            'liberados. Atendimentos passados não são afetados.',
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
              child: const Text('Excluir'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final sb = Supabase.instance.client;
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      // 1. Libera os horários futuros já gerados por esta recorrência.
      //    Mantém atendimentos passados (histórico/caixa) intactos.
      await sb
          .from('appointments')
          .delete()
          .eq('recurring_schedule_id', sched['id'])
          .gte('appointment_date', today)
          .inFilter('status', ['scheduled', 'confirmed']);

      // 2. Remove a recorrência em si.
      await sb.from('recurring_schedules').delete().eq('id', sched['id']);

      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recorrência removida e horários liberados.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Recorrente • ${widget.planClientName}'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openDialog,
        tooltip: 'Novo agendamento recorrente',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _schedules.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.repeat_rounded,
                    size: 72,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum recorrente cadastrado',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toque em + para adicionar',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _schedules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s          = _schedules[i];
                final barberMap  = s['barbers']  is Map ? s['barbers']  as Map : {};
                final serviceMap = s['services'] is Map ? s['services'] as Map : {};
                final barberName  = barberMap['name']?.toString()  ?? '—';
                final serviceName = serviceMap['name']?.toString() ?? '—';
                final blocks  = (serviceMap['duration_blocks'] as int?) ?? 1;
                final time    = (s['appointment_time'] as String? ?? '').substring(0, 5);
                final day     = _kDays[s['day_of_week'] as int? ?? 0];
                final isActive = s['is_active'] as bool? ?? true;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: isActive
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.repeat_rounded,
                            color: isActive
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Conteúdo flexível — usa o espaço restante e trunca
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$day às $time',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$serviceName  •  $barberName',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$blocks bloco${blocks > 1 ? 's' : ''} de 30 min  •  '
                                '${isActive ? 'Ativo' : 'Inativo'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isActive
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Ações compactas — pausar/reativar visível + menu
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                isActive
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline,
                                color: isActive
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline,
                              ),
                              tooltip: isActive ? 'Pausar' : 'Reativar',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _toggleActive(s),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              tooltip: 'Mais opções',
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _openDialog(sched: s);
                                } else if (v == 'delete') {
                                  _delete(s);
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
                                        'Excluir',
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
