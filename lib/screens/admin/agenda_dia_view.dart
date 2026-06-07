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

  InputDecoration _dlgDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _gold, width: 1.5),
        ),
      );

  /// Agendamento manual feito pelo admin a partir de um slot livre.
  /// Grava como `source = 'admin'` (fica roxo) e ocupa o horário.
  Future<void> _openManualBooking(_Slot startSlot) async {
    List<Map<String, dynamic>> services = [];
    try {
      final rows = await Supabase.instance.client
          .from('services')
          .select('id,name,price')
          .order('name');
      services = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _toast('Erro ao carregar serviços: $e');
      return;
    }
    if (!mounted || services.isEmpty) {
      if (services.isEmpty) _toast('Nenhum serviço cadastrado.');
      return;
    }

    final selectedIds = <String>{};
    final nameCtr = TextEditingController();
    final phoneCtr = TextEditingController();
    bool saving = false;
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: _card,
          title: Text('Agendar • ${startSlot.label}',
              style: const TextStyle(color: _text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Serviços:',
                    style: TextStyle(color: _muted, fontSize: 12)),
                ...services.map((s) {
                  final id = s['id'].toString();
                  final price = (s['price'] as num? ?? 0).toDouble();
                  return CheckboxListTile(
                    value: selectedIds.contains(id),
                    onChanged: (v) => setSt(() {
                      if (v == true) {
                        selectedIds.add(id);
                      } else {
                        selectedIds.remove(id);
                      }
                    }),
                    title: Text(s['name']?.toString() ?? '',
                        style: const TextStyle(color: _text)),
                    subtitle: Text(
                      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                          .format(price),
                      style: const TextStyle(color: _muted),
                    ),
                    activeColor: _gold,
                    checkColor: Colors.black,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  );
                }),
                const Divider(color: _border),
                TextField(
                  controller: nameCtr,
                  style: const TextStyle(color: _text),
                  decoration: _dlgDeco('Nome do cliente'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtr,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: _text),
                  decoration: _dlgDeco('Telefone'),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(err!,
                        style: const TextStyle(
                            color: Color(0xFFF06666), fontSize: 12)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: _muted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFA888F5),
                  foregroundColor: Colors.black),
              onPressed: saving
                  ? null
                  : () async {
                      if (selectedIds.isEmpty) {
                        setSt(() => err = 'Selecione ao menos um serviço.');
                        return;
                      }
                      if (nameCtr.text.trim().isEmpty) {
                        setSt(() => err = 'Informe o nome do cliente.');
                        return;
                      }
                      setSt(() {
                        saving = true;
                        err = null;
                      });
                      final chosen = services
                          .where((s) => selectedIds.contains(s['id'].toString()))
                          .toList();
                      final res = await _saveManual(
                        startSlot,
                        chosen,
                        nameCtr.text.trim(),
                        phoneCtr.text.trim(),
                      );
                      if (res != null) {
                        setSt(() {
                          saving = false;
                          err = res;
                        });
                        return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Agendar'),
            ),
          ],
        ),
      ),
    );
    await _load();
  }

  /// Valida os slots consecutivos e grava o(s) agendamento(s) manual(is).
  /// Retorna null em sucesso, ou a mensagem de erro.
  Future<String?> _saveManual(
    _Slot startSlot,
    List<Map<String, dynamic>> services,
    String name,
    String phone,
  ) async {
    final n = services.length;
    final startIdx = _slots.indexWhere((s) => s.label == startSlot.label);
    if (startIdx < 0) return 'Horário inválido.';
    if (startIdx + n > _slots.length) {
      return 'Não há $n horários seguidos livres a partir das ${startSlot.label}.';
    }
    for (var k = 0; k < n; k++) {
      final s = _slots[startIdx + k];
      if (s.state != _SlotState.free) {
        return 'O horário ${s.label} não está livre.';
      }
    }
    try {
      final sb = Supabase.instance.client;
      bool isPlan = false;
      final normPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (normPhone.length >= 10) {
        try {
          final pc = await sb
              .from('plan_clients')
              .select('id')
              .eq('phone', normPhone)
              .limit(1);
          isPlan = pc.isNotEmpty;
        } catch (_) {}
      }
      final payload = <Map<String, dynamic>>[];
      for (var i = 0; i < n; i++) {
        final s = services[i];
        final label = _slots[startIdx + i].label;
        payload.add({
          'service_id': s['id'],
          'barber_id': widget.barberId,
          'appointment_date': _dateStr,
          'appointment_time': '$label:00',
          'status': 'scheduled',
          'customer_name': name,
          'customer_phone': phone,
          'notes': 'Encaixe manual (admin)\nCliente: $name\nTelefone: $phone',
          'total_price': (s['price'] as num? ?? 0).toDouble(),
          'is_plan_client': isPlan,
          'source': 'admin',
        });
      }
      await sb.from('appointments').insert(payload);
      return null;
    } catch (e) {
      return 'Erro ao agendar: $e';
    }
  }

  void _onTapSlot(_Slot slot) {
    if (slot.state == _SlotState.free) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _card,
          title: Text('Horário ${slot.label}',
              style: const TextStyle(color: _text)),
          content: const Text('Horário livre. O que deseja fazer?',
              style: TextStyle(color: _muted)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: _muted)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _block(slot);
              },
              child: const Text('Bloquear',
                  style: TextStyle(color: Color(0xFFF06666))),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: _gold, foregroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(ctx);
                _openManualBooking(slot);
              },
              child: const Text('Agendar'),
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

  // Cor sólida do card (estilo da referência)
  Color _bgFor(_SlotState s) {
    switch (s) {
      case _SlotState.free:
        return const Color(0xFF3C3C3C); // cinza escuro (vago)
      case _SlotState.client:
        return const Color(0xFFDCDCDC); // cinza claro (cliente)
      case _SlotState.newClient:
        return const Color(0xFFB9D2F5); // azul claro (novo)
      case _SlotState.admin:
        return const Color(0xFFCBA6F5); // roxo (encaixe)
      case _SlotState.blocked:
        return const Color(0xFFF2B5B5); // vermelho claro (bloqueado)
    }
  }

  // Cor do texto sobre o card
  Color _fgFor(_SlotState s) {
    switch (s) {
      case _SlotState.free:
        return const Color(0xFFC8C8C8);
      case _SlotState.client:
        return const Color(0xFF161616);
      case _SlotState.newClient:
        return const Color(0xFF14233A);
      case _SlotState.admin:
        return const Color(0xFF2A1648);
      case _SlotState.blocked:
        return const Color(0xFF7A1F1F);
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
    final fg = _fgFor(slot.state);
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
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    slot.label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  child: booked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              slot.name.isEmpty ? 'Cliente' : slot.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (slot.service.isNotEmpty)
                              Text(
                                slot.service,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: fg.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        )
                      : Text(
                          slot.state == _SlotState.blocked
                              ? 'Bloqueado'
                              : 'Livre',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                if (slot.state == _SlotState.newClient ||
                    slot.state == _SlotState.admin)
                  Text(
                    slot.state == _SlotState.newClient ? 'NOVO' : 'ENCAIXE',
                    style: TextStyle(
                      color: fg,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                if (slot.state == _SlotState.blocked)
                  Icon(Icons.lock_outline, color: fg, size: 16),
              ],
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
        item(_bgFor(_SlotState.free), 'Vago'),
        item(_bgFor(_SlotState.client), 'Cliente'),
        item(_bgFor(_SlotState.newClient), 'Novo'),
        item(_bgFor(_SlotState.admin), 'Encaixe'),
        item(_bgFor(_SlotState.blocked), 'Bloqueado'),
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
