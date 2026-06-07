import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Estados possíveis de um slot de 30 min na agenda do dia.
enum _SlotState { free, client, newClient, admin, blocked }

class _Slot {
  _Slot(this.label);
  final String label; // "HH:mm"
  _SlotState state = _SlotState.free;
  String name = '';
  String service = '';
  String phone = '';
  String? blockedId; // id na tabela blocked_slots (p/ desbloquear)
}

/// Agenda do dia (lista vertical, slot a slot, colorida por tipo).
/// Substitui a visão "Dia" da tela de Agendamentos.
class AgendaDiaView extends StatefulWidget {
  const AgendaDiaView({
    super.key,
    required this.date,
    required this.barberId,
    required this.barbers,
  });

  final DateTime date;
  final String? barberId;
  final List<Map<String, dynamic>> barbers;

  @override
  State<AgendaDiaView> createState() => _AgendaDiaViewState();
}

class _AgendaDiaViewState extends State<AgendaDiaView> {
  // Paleta (mesma do app)
  static const _card = Color(0xFF111111);
  static const _border = Color(0xFF222222);
  static const _gold = Color(0xFFF5C200);
  static const _text = Color(0xFFF0EDE8);
  static const _muted = Color(0xFF6B7280);

  bool _loading = true;
  String? _error;
  List<_Slot> _slots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AgendaDiaView old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date || old.barberId != widget.barberId) {
      _load();
    }
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(widget.date);

  Future<void> _load() async {
    if (widget.barberId == null) {
      setState(() {
        _loading = false;
        _slots = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final sb = Supabase.instance.client;
    final barberId = widget.barberId!;

    try {
      // 1. Disponibilidade (início/fim) do barbeiro nesse dia da semana
      final dow = widget.date.weekday; // 1..7 (Seg..Dom)
      TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
      TimeOfDay end = const TimeOfDay(hour: 18, minute: 0);
      bool enabled = true;
      final avRows = await sb
          .from('barber_availability')
          .select('start_time,end_time,is_available')
          .eq('barber_id', barberId)
          .eq('day_of_week', dow == 7 ? 0 : dow)
          .limit(1);
      if (avRows.isNotEmpty) {
        final row = avRows.first;
        enabled = (row['is_available'] ?? true) == true;
        start = _parse('${row['start_time'] ?? '09:00:00'}', 9, 0);
        end = _parse('${row['end_time'] ?? '18:00:00'}', 18, 0);
      }

      // 2. Gera os slots de 30 min
      final slots = <_Slot>[];
      if (enabled) {
        var cur = DateTime(0, 1, 1, start.hour, start.minute);
        final endDt = DateTime(0, 1, 1, end.hour, end.minute);
        while (!cur.isAfter(endDt)) {
          slots.add(_Slot(
            '${cur.hour.toString().padLeft(2, '0')}:'
            '${cur.minute.toString().padLeft(2, '0')}',
          ));
          cur = cur.add(const Duration(minutes: 30));
        }
      }
      final byLabel = {for (final s in slots) s.label: s};

      // 3. Agendamentos do barbeiro nesse dia
      final apptRows = await sb
          .from('appointments')
          .select(
            'appointment_time,customer_name,customer_phone,status,source,services:service_id(name)',
          )
          .eq('barber_id', barberId)
          .eq('appointment_date', _dateStr);

      final phones = <String>{};
      final appts = <Map<String, dynamic>>[];
      for (final r in (apptRows as List)) {
        final m = r as Map<String, dynamic>;
        final st = (m['status'] ?? '').toString().toLowerCase();
        if (st == 'cancelled' || st == 'no_show') continue;
        appts.add(m);
        final ph = (m['customer_phone'] ?? '').toString().trim();
        if (ph.isNotEmpty) phones.add(ph);
      }

      // 4. Quais telefones já tiveram agendamento ANTES desse dia (retornantes)
      final returning = <String>{};
      if (phones.isNotEmpty) {
        final prior = await sb
            .from('appointments')
            .select('customer_phone')
            .inFilter('customer_phone', phones.toList())
            .lt('appointment_date', _dateStr);
        for (final r in (prior as List)) {
          final ph = ((r as Map)['customer_phone'] ?? '').toString().trim();
          if (ph.isNotEmpty) returning.add(ph);
        }
      }

      // 5. Horários bloqueados
      final blockedRows = await sb
          .from('blocked_slots')
          .select('id,time')
          .eq('barber_id', barberId)
          .eq('date', _dateStr);
      for (final r in (blockedRows as List)) {
        final m = r as Map<String, dynamic>;
        final label = _hhmm('${m['time']}');
        final slot = byLabel[label];
        if (slot != null) {
          slot.state = _SlotState.blocked;
          slot.blockedId = m['id']?.toString();
        }
      }

      // 6. Preenche os slots com os agendamentos
      for (final m in appts) {
        final label = _hhmm('${m['appointment_time']}');
        final slot = byLabel[label];
        if (slot == null) continue;
        if (slot.state == _SlotState.blocked) continue; // bloqueio tem prioridade
        final source = (m['source'] ?? 'client').toString();
        final ph = (m['customer_phone'] ?? '').toString().trim();
        slot.name = (m['customer_name'] ?? '').toString().trim();
        slot.phone = ph;
        slot.service = _serviceName(m['services']);
        if (source == 'admin') {
          slot.state = _SlotState.admin;
        } else if (ph.isNotEmpty && !returning.contains(ph)) {
          slot.state = _SlotState.newClient;
        } else {
          slot.state = _SlotState.client;
        }
      }

      if (!mounted) return;
      setState(() {
        _slots = slots;
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

  TimeOfDay _parse(String raw, int dh, int dm) {
    final p = raw.split(':');
    return TimeOfDay(
      hour: int.tryParse(p[0]) ?? dh,
      minute: p.length > 1 ? (int.tryParse(p[1]) ?? dm) : dm,
    );
  }

  String _hhmm(String raw) {
    final p = raw.split(':');
    if (p.length < 2) return raw;
    return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
  }

  String _serviceName(dynamic services) {
    if (services is Map) return services['name']?.toString() ?? '';
    if (services is List && services.isNotEmpty) {
      return services
          .map((s) => s is Map ? (s['name']?.toString() ?? '') : '')
          .where((n) => n.isNotEmpty)
          .join(', ');
    }
    return '';
  }

  // ── Ações ───────────────────────────────────────────────────────────────────

  Future<void> _block(_Slot slot) async {
    try {
      await Supabase.instance.client.from('blocked_slots').insert({
        'barber_id': widget.barberId,
        'date': _dateStr,
        'time': '${slot.label}:00',
      });
      await _load();
    } catch (e) {
      _toast('Erro ao bloquear: $e');
    }
  }

  Future<void> _unblock(_Slot slot) async {
    try {
      final q = Supabase.instance.client.from('blocked_slots').delete();
      if (slot.blockedId != null) {
        await q.eq('id', slot.blockedId!);
      } else {
        await q
            .eq('barber_id', widget.barberId!)
            .eq('date', _dateStr)
            .eq('time', '${slot.label}:00');
      }
      await _load();
    } catch (e) {
      _toast('Erro ao desbloquear: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onTapSlot(_Slot slot) {
    if (slot.state == _SlotState.free) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _card,
          title: Text('Horário ${slot.label}',
              style: const TextStyle(color: _text)),
          content: const Text('Bloquear este horário? Ele ficará indisponível para agendamento.',
              style: TextStyle(color: _muted)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: _muted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () {
                Navigator.pop(ctx);
                _block(slot);
              },
              child: const Text('Bloquear'),
            ),
          ],
        ),
      );
    } else if (slot.state == _SlotState.blocked) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _card,
          title: Text('Horário ${slot.label}',
              style: const TextStyle(color: _text)),
          content: const Text('Desbloquear este horário?',
              style: TextStyle(color: _muted)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: _muted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(ctx);
                _unblock(slot);
              },
              child: const Text('Desbloquear'),
            ),
          ],
        ),
      );
    } else {
      // agendado → mostra detalhes
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _card,
          title: Text(slot.name.isEmpty ? 'Agendamento' : slot.name,
              style: const TextStyle(color: _text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Horário: ${slot.label}', style: const TextStyle(color: _muted)),
              if (slot.service.isNotEmpty)
                Text('Serviço: ${slot.service}', style: const TextStyle(color: _muted)),
              if (slot.phone.isNotEmpty)
                Text('Telefone: ${slot.phone}', style: const TextStyle(color: _muted)),
              const SizedBox(height: 6),
              Text(_stateLabel(slot.state),
                  style: TextStyle(color: _accent(slot.state), fontWeight: FontWeight.w700)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar', style: TextStyle(color: _gold)),
            ),
          ],
        ),
      );
    }
  }

  // ── Cores por estado ────────────────────────────────────────────────────────

  Color _bgFor(_SlotState s) {
    switch (s) {
      case _SlotState.free:
        return const Color(0xFF141414);
      case _SlotState.client:
        return const Color(0xFF202228);
      case _SlotState.newClient:
        return const Color(0xFF12263D);
      case _SlotState.admin:
        return const Color(0xFF2A1F45);
      case _SlotState.blocked:
        return const Color(0xFF3A1A1A);
    }
  }

  Color _accent(_SlotState s) {
    switch (s) {
      case _SlotState.free:
        return _muted;
      case _SlotState.client:
        return const Color(0xFFCBD5E1);
      case _SlotState.newClient:
        return const Color(0xFF5AA2F0);
      case _SlotState.admin:
        return const Color(0xFFA888F5);
      case _SlotState.blocked:
        return const Color(0xFFF06666);
    }
  }

  String _stateLabel(_SlotState s) {
    switch (s) {
      case _SlotState.free:
        return 'Livre';
      case _SlotState.client:
        return 'Cliente';
      case _SlotState.newClient:
        return 'Cliente novo';
      case _SlotState.admin:
        return 'Encaixe (admin)';
      case _SlotState.blocked:
        return 'Bloqueado';
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.barberId == null) {
      return _box('Selecione um barbeiro acima para ver a agenda do dia.');
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }
    if (_error != null) {
      return _box('Erro: $_error');
    }
    if (_slots.isEmpty) {
      return _box('Sem expediente para este dia.');
    }

    final barberName = widget.barbers.firstWhere(
      (b) => b['id']?.toString() == widget.barberId,
      orElse: () => const {'name': ''},
    )['name']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _legend(),
        const SizedBox(height: 10),
        if (barberName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              '$barberName • ${DateFormat("EEEE, dd/MM", 'pt_BR').format(widget.date)}',
              style: const TextStyle(
                  color: _gold, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ..._slots.map(_slotRow),
      ],
    );
  }

  Widget _slotRow(_Slot slot) {
    final accent = _accent(slot.state);
    final booked = slot.state == _SlotState.client ||
        slot.state == _SlotState.newClient ||
        slot.state == _SlotState.admin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _onTapSlot(slot),
          child: Container(
            decoration: BoxDecoration(
              color: _bgFor(slot.state),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Barra de cor + hora
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        bottomLeft: Radius.circular(10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    child: Text(
                      slot.label,
                      style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: booked
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  slot.name.isEmpty ? 'Cliente' : slot.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (slot.service.isNotEmpty)
                                  Text(
                                    slot.service,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: _muted, fontSize: 12),
                                  ),
                              ],
                            )
                          : Text(
                              slot.state == _SlotState.blocked
                                  ? 'Bloqueado'
                                  : 'Livre',
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  // Selo do tipo (cliente novo / encaixe)
                  if (slot.state == _SlotState.newClient ||
                      slot.state == _SlotState.admin)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        slot.state == _SlotState.newClient ? 'NOVO' : 'ENCAIXE',
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  if (slot.state == _SlotState.blocked)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.lock_outline,
                          color: Color(0xFFF06666), size: 16),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend() {
    Widget item(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(color: _muted, fontSize: 11)),
          ],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        item(const Color(0xFF3A3A3A), 'Vago'),
        item(const Color(0xFFCBD5E1), 'Cliente'),
        item(const Color(0xFF5AA2F0), 'Novo'),
        item(const Color(0xFFA888F5), 'Encaixe'),
        item(const Color(0xFFF06666), 'Bloqueado'),
      ],
    );
  }

  Widget _box(String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Text(msg, style: const TextStyle(color: _muted)),
      );
}
