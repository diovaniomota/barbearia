import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/models/service.dart';

/// Estados possíveis de um slot de 30 min na agenda do dia.
enum _SlotState { free, client, newClient, admin, blocked }

class _Slot {
  _Slot(this.label);
  final String label; // "HH:mm"
  _SlotState state = _SlotState.free;
  String name = '';
  String service = '';
  String phone = '';
  String? blockedId;      // id na tabela blocked_slots (p/ desbloquear)
  String? appointmentId;  // id do appointment com total_price > 0
  double? totalPrice;
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
  static const _red = Color(0xFFF06666);

  bool _loading = true;
  String? _error;
  List<_Slot> _slots = [];

  bool _selectMode = false;
  final Set<String> _selectedLabels = {};

  // id do registro em barber_blocked_days que cobre esta data (null = dia livre)
  String? _dayBlockId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AgendaDiaView old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date || old.barberId != widget.barberId) {
      _selectMode = false;
      _selectedLabels.clear();
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
          .select('start_time,end_time,is_available,break_start,break_end')
          .eq('barber_id', barberId)
          .eq('day_of_week', dow == 7 ? 0 : dow)
          .limit(1);
      DateTime? breakStartDt;
      DateTime? breakEndDt;
      if (avRows.isNotEmpty) {
        final row = avRows.first;
        enabled = (row['is_available'] ?? true) == true;
        start = _parse('${row['start_time'] ?? '09:00:00'}', 9, 0);
        end = _parse('${row['end_time'] ?? '18:00:00'}', 18, 0);
        final bsRaw = row['break_start']?.toString();
        final beRaw = row['break_end']?.toString();
        if (bsRaw != null && bsRaw.isNotEmpty && bsRaw != 'null') {
          final bs = _parse(bsRaw, 12, 0);
          breakStartDt = DateTime(0, 1, 1, bs.hour, bs.minute);
        }
        if (beRaw != null && beRaw.isNotEmpty && beRaw != 'null') {
          final be = _parse(beRaw, 14, 0);
          breakEndDt = DateTime(0, 1, 1, be.hour, be.minute);
        }
      }

      // 2. Gera os slots de 30 min (pulando a pausa se configurada)
      final slots = <_Slot>[];
      if (enabled) {
        var cur = DateTime(0, 1, 1, start.hour, start.minute);
        final endDt = DateTime(0, 1, 1, end.hour, end.minute);
        while (!cur.isAfter(endDt)) {
          final duringBreak =
              breakStartDt != null &&
              breakEndDt != null &&
              !cur.isBefore(breakStartDt) &&
              cur.isBefore(breakEndDt);
          if (!duringBreak) {
            slots.add(
              _Slot(
                '${cur.hour.toString().padLeft(2, '0')}:'
                '${cur.minute.toString().padLeft(2, '0')}',
              ),
            );
          }
          cur = cur.add(const Duration(minutes: 30));
        }
      }
      final byLabel = {for (final s in slots) s.label: s};

      // 3. Agendamentos do barbeiro nesse dia
      final apptRows = await sb
          .from('appointments')
          .select(
            'id,appointment_time,customer_name,customer_phone,status,source,total_price,services:service_id(name)',
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

      // 5. Dia inteiro bloqueado (barber_blocked_days)
      try {
        final dayBlocks = await sb
            .from('barber_blocked_days')
            .select('id')
            .eq('barber_id', barberId)
            .lte('date_from', _dateStr)
            .gte('date_to', _dateStr)
            .limit(1);
        _dayBlockId = dayBlocks.isNotEmpty
            ? dayBlocks.first['id'].toString()
            : null;
      } catch (_) {
        _dayBlockId = null;
      }

      // 6. Horários bloqueados individualmente (blocked_slots)
      final blockedRows = await sb
          .from('blocked_slots')
          .select('id,time')
          .eq('barber_id', barberId)
          .eq('date', _dateStr);
      for (final r in (blockedRows as List)) {
        final m = r as Map<String, dynamic>;
        final label = _hhmm('${m['time']}');
        // Bloqueio fora do expediente (horário extra) também precisa aparecer.
        var slot = byLabel[label];
        if (slot == null) {
          slot = _Slot(label);
          byLabel[label] = slot;
          slots.add(slot);
        }
        slot.state = _SlotState.blocked;
        slot.blockedId = m['id']?.toString();
      }

      // 7. Preenche os slots com os agendamentos
      for (final m in appts) {
        final label = _hhmm('${m['appointment_time']}');
        // Agendamento fora do expediente (horário extra) também precisa aparecer.
        var slot = byLabel[label];
        if (slot == null) {
          slot = _Slot(label);
          byLabel[label] = slot;
          slots.add(slot);
        }
        if (slot.state == _SlotState.blocked) {
          continue; // bloqueio tem prioridade
        }
        final source = (m['source'] ?? 'client').toString();
        final ph = (m['customer_phone'] ?? '').toString().trim();
        slot.name    = (m['customer_name'] ?? '').toString().trim();
        slot.phone   = ph;
        slot.service = _serviceName(m['services']);
        final rowPrice = (m['total_price'] as num?)?.toDouble() ?? 0.0;
        if (rowPrice > 0 || slot.appointmentId == null) {
          slot.appointmentId = m['id']?.toString();
          if (rowPrice > 0) slot.totalPrice = rowPrice;
        }
        if (source == 'admin') {
          slot.state = _SlotState.admin;
        } else if (ph.isNotEmpty && !returning.contains(ph)) {
          slot.state = _SlotState.newClient;
        } else {
          slot.state = _SlotState.client;
        }
      }

      // Ordena por horário (labels "HH:mm" já são comparáveis como string),
      // garantindo que horários extras fiquem na posição certa.
      slots.sort((a, b) => a.label.compareTo(b.label));

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

  // ── Seleção múltipla ────────────────────────────────────────────────────────

  void _toggleSelect(_Slot slot) {
    setState(() {
      if (_selectedLabels.contains(slot.label)) {
        _selectedLabels.remove(slot.label);
      } else {
        _selectedLabels.add(slot.label);
      }
    });
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

  /// Bloqueia o dia inteiro (ou um período) para o barbeiro.
  Future<void> _blockDay(String dateFrom, String dateTo) async {
    try {
      await Supabase.instance.client.from('barber_blocked_days').insert({
        'barber_id': widget.barberId,
        'date_from': dateFrom,
        'date_to': dateTo,
      });
      await _load();
      _toast('Dia(s) bloqueado(s) com sucesso.');
    } catch (e) {
      _toast('Erro ao bloquear: $e');
    }
  }

  /// Remove o bloqueio de dia inteiro desta data.
  Future<void> _unblockDay() async {
    if (_dayBlockId == null) return;
    try {
      final deleted = await Supabase.instance.client
          .from('barber_blocked_days')
          .delete()
          .eq('id', _dayBlockId!)
          .select();
      if (deleted.isEmpty) {
        _toast(
          'Sem permissão para desbloquear. Verifique a política RLS da tabela barber_blocked_days.',
        );
        return;
      }
      _dayBlockId = null;
      await _load();
      _toast('Bloqueio removido.');
    } catch (e) {
      _toast('Erro ao desbloquear: $e');
    }
  }

  /// Dialog para o admin escolher bloquear só este dia ou um período.
  Future<void> _openBlockDayDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text(
          'Bloquear disponibilidade',
          style: TextStyle(color: _text),
        ),
        content: const Text(
          'O barbeiro não estará disponível para agendamentos no período selecionado.',
          style: TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'day'),
            child: const Text('Este dia', style: TextStyle(color: _red)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, 'period'),
            child: const Text('Período'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'day') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: _card,
          title: const Text(
            'Confirmar bloqueio',
            style: TextStyle(color: _text),
          ),
          content: Text(
            'Bloquear ${DateFormat("dd/MM/yyyy", 'pt_BR').format(widget.date)}?\n\nO barbeiro não aparecerá disponível para os clientes neste dia.',
            style: const TextStyle(color: _muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Não', style: TextStyle(color: _muted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Bloquear'),
            ),
          ],
        ),
      );
      if (confirm == true) await _blockDay(_dateStr, _dateStr);
    } else {
      // Seleção de período com date range picker
      if (!mounted) return;
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: DateTimeRange(start: widget.date, end: widget.date),
        locale: const Locale('pt', 'BR'),
        helpText: 'Selecione o período de bloqueio',
        saveText: 'CONFIRMAR',
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        ),
      );
      if (range == null || !mounted) return;
      final from = DateFormat('yyyy-MM-dd').format(range.start);
      final to = DateFormat('yyyy-MM-dd').format(range.end);
      await _blockDay(from, to);
    }
  }

  /// Cancela os agendamentos dos slots informados.
  /// O horário volta a ficar livre para novos agendamentos.
  Future<void> _cancelAndBlock(List<_Slot> slots) async {
    if (slots.isEmpty) return;
    final sb = Supabase.instance.client;
    final booked = slots
        .where(
          (s) =>
              s.state == _SlotState.client ||
              s.state == _SlotState.newClient ||
              s.state == _SlotState.admin,
        )
        .toList();
    if (booked.isEmpty) {
      _toast('Nenhum agendamento selecionado para cancelar.');
      setState(() {
        _selectMode = false;
        _selectedLabels.clear();
      });
      return;
    }
    try {
      for (final slot in booked) {
        await sb
            .from('appointments')
            .update({'status': 'cancelled'})
            .eq('barber_id', widget.barberId!)
            .eq('appointment_date', _dateStr)
            .eq('appointment_time', '${slot.label}:00');
      }
      if (mounted) {
        setState(() {
          _selectMode = false;
          _selectedLabels.clear();
        });
      }
      await _load();
      _toast('${booked.length} agendamento(s) cancelado(s).');
    } catch (e) {
      _toast('Erro ao cancelar: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Arredonda um horário para o slot de 30 min mais próximo (xx:00 ou xx:30).
  TimeOfDay _snap(TimeOfDay t) {
    var h = t.hour;
    int m;
    if (t.minute < 15) {
      m = 0;
    } else if (t.minute < 45) {
      m = 30;
    } else {
      m = 0;
      h = (h + 1) % 24;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  /// Adiciona um horário extra (fora do expediente) só para este dia.
  /// O slot vira "Livre" na agenda; o admin toca nele para agendar/encaixar.
  Future<void> _addExtraSlot() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
      helpText: 'Horário extra para este dia',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final t = _snap(picked);
    final label =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    if (_slots.any((s) => s.label == label)) {
      _toast('O horário $label já está na agenda.');
      return;
    }

    setState(() {
      _slots.add(_Slot(label));
      _slots.sort((a, b) => a.label.compareTo(b.label));
    });
    _toast('Horário $label adicionado. Toque nele para agendar.');
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
          .select('id,name,price,sort_order,duration_blocks')
          .order('name');
      services = List<Map<String, dynamic>>.from(rows)
        ..sort((a, b) {
          final c = Service.parseInt(
            a['sort_order'],
          ).compareTo(Service.parseInt(b['sort_order']));
          return c != 0
              ? c
              : '${a['name']}'.toLowerCase().compareTo(
                  '${b['name']}'.toLowerCase(),
                );
        });
    } catch (e) {
      _toast('Erro ao carregar serviços: $e');
      return;
    }
    if (!mounted || services.isEmpty) {
      if (services.isEmpty) _toast('Nenhum serviço cadastrado.');
      return;
    }

    final selectedIds = <String>{};
    final nameCtr  = TextEditingController();
    final phoneCtr = TextEditingController();
    final priceCtr = TextEditingController();
    bool priceEdited = false;

    double calcTotal() => services
        .where((s) => selectedIds.contains(s['id'].toString()))
        .fold(0.0, (sum, s) => sum + (s['price'] as num? ?? 0).toDouble());

    void syncPrice() {
      if (!priceEdited) {
        final total = calcTotal();
        priceCtr.text = total > 0
            ? total.toStringAsFixed(2).replaceAll('.', ',')
            : '';
      }
    }

    bool saving = false;
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: _card,
          title: Text(
            'Agendar • ${startSlot.label}',
            style: const TextStyle(color: _text),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Serviços:',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
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
                      syncPrice();
                    }),
                    title: Text(
                      s['name']?.toString() ?? '',
                      style: const TextStyle(color: _text),
                    ),
                    subtitle: Text(
                      NumberFormat.currency(
                        locale: 'pt_BR',
                        symbol: 'R\$',
                      ).format(price),
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
                  controller: priceCtr,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: _text),
                  decoration: _dlgDeco('Valor cobrado (R\$)').copyWith(
                    hintText: 'Preço do serviço',
                    hintStyle: const TextStyle(color: _muted),
                    helperText: 'Deixe em branco ou edite para dar desconto',
                    helperStyle: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  onChanged: (_) => priceEdited = true,
                ),
                const SizedBox(height: 10),
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
                    child: Text(
                      err!,
                      style: const TextStyle(color: _red, fontSize: 12),
                    ),
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
                foregroundColor: Colors.black,
              ),
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
                          .where(
                            (s) => selectedIds.contains(s['id'].toString()),
                          )
                          .toList();
                      final customPrice = double.tryParse(
                        priceCtr.text.trim().replaceAll(',', '.'),
                      );
                      final res = await _saveManual(
                        startSlot,
                        chosen,
                        nameCtr.text.trim(),
                        phoneCtr.text.trim(),
                        customPrice: customPrice,
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
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
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
    String phone, {
    double? customPrice,
  }) async {
    // Total de blocos de 30 min considerando duration_blocks de cada serviço
    final n = services.fold<int>(
      0,
      (sum, s) => sum + ((s['duration_blocks'] as int?) ?? 1),
    );
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
      var slotOffset = 0;
      bool customPriceApplied = false;
      for (final s in services) {
        final blocks = (s['duration_blocks'] as int?) ?? 1;
        final servicePrice = (s['price'] as num? ?? 0).toDouble();
        for (var k = 0; k < blocks; k++) {
          double rowPrice = 0.0;
          if (customPrice != null) {
            // Preço customizado: apenas o primeiro slot recebe o valor informado
            if (!customPriceApplied) {
              rowPrice = customPrice;
              customPriceApplied = true;
            }
          } else {
            // Preço padrão: primeiro bloco de cada serviço recebe o preço do serviço
            rowPrice = k == 0 ? servicePrice : 0.0;
          }
          final label = _slots[startIdx + slotOffset].label;
          payload.add({
            'service_id': s['id'],
            'barber_id': widget.barberId,
            'appointment_date': _dateStr,
            'appointment_time': '$label:00',
            'status': 'scheduled',
            'customer_name': name,
            'customer_phone': phone,
            'notes':
                'Encaixe manual (admin)\nCliente: $name\nTelefone: $phone',
            'total_price': rowPrice,
            'is_plan_client': isPlan,
            'source': 'admin',
          });
          slotOffset++;
        }
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
          title: Text(
            'Horário ${slot.label}',
            style: const TextStyle(color: _text),
          ),
          content: const Text(
            'Horário livre. O que deseja fazer?',
            style: TextStyle(color: _muted),
          ),
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
              child: const Text('Bloquear', style: TextStyle(color: _red)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
              ),
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
          title: Text(
            'Horário ${slot.label}',
            style: const TextStyle(color: _text),
          ),
          content: const Text(
            'Desbloquear este horário?',
            style: TextStyle(color: _muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: _muted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
              ),
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
      // agendado → mostra detalhes + opção de cancelar
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _card,
          title: Text(
            slot.name.isEmpty ? 'Agendamento' : slot.name,
            style: const TextStyle(color: _text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Horário: ${slot.label}',
                style: const TextStyle(color: _muted),
              ),
              if (slot.service.isNotEmpty)
                Text(
                  'Serviço: ${slot.service}',
                  style: const TextStyle(color: _muted),
                ),
              if (slot.phone.isNotEmpty)
                Text(
                  'Telefone: ${slot.phone}',
                  style: const TextStyle(color: _muted),
                ),
              const SizedBox(height: 6),
              Text(
                _stateLabel(slot.state),
                style: TextStyle(
                  color: _accent(slot.state),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar', style: TextStyle(color: _gold)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _editPrice(slot);
              },
              child: const Text('Editar valor', style: TextStyle(color: _gold)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: _card,
                    title: const Text(
                      'Cancelar agendamento?',
                      style: TextStyle(color: _text),
                    ),
                    content: const Text(
                      'O agendamento será cancelado e o horário ficará livre novamente.',
                      style: TextStyle(color: _muted),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text(
                          'Não',
                          style: TextStyle(color: _muted),
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _cancelAndBlock([slot]);
                }
              },
              child: const Text(
                'Cancelar agendamento',
                style: TextStyle(color: _red),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _editPrice(_Slot slot) async {
    if (slot.appointmentId == null) return;
    final priceCtr = TextEditingController(
      text: slot.totalPrice != null
          ? slot.totalPrice!.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Editar valor cobrado', style: TextStyle(color: _text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              slot.service.isNotEmpty ? slot.service : 'Serviço',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtr,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: _text),
              decoration: _dlgDeco('Valor cobrado (R\$)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: _muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final newPrice = double.tryParse(priceCtr.text.trim().replaceAll(',', '.'));
    if (newPrice == null) return;
    try {
      await Supabase.instance.client
          .from('appointments')
          .update({'total_price': newPrice})
          .eq('id', slot.appointmentId!);
      _toast('Valor atualizado para R\$ ${newPrice.toStringAsFixed(2).replaceAll('.', ',')}');
      await _load();
    } catch (e) {
      _toast('Erro ao atualizar: $e');
    }
  }

  // ── Cores por estado ────────────────────────────────────────────────────────

  Color _bgFor(_SlotState s) {
    switch (s) {
      case _SlotState.free:
        return const Color(0xFF3C3C3C);
      case _SlotState.client:
        return const Color(0xFFDCDCDC);
      case _SlotState.newClient:
        return const Color(0xFFB9D2F5);
      case _SlotState.admin:
        return const Color(0xFFCBA6F5);
      case _SlotState.blocked:
        return const Color(0xFFF2B5B5);
    }
  }

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
        return _red;
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

  // ── Barra de seleção múltipla ───────────────────────────────────────────────

  Widget _selectBar() {
    if (!_selectMode) {
      const compact = ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
        minimumSize: WidgetStatePropertyAll(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 2,
        children: [
          TextButton.icon(
            onPressed: _addExtraSlot,
            icon: const Icon(Icons.more_time_rounded, color: _gold, size: 16),
            label: const Text(
              'Adicionar horário',
              style: TextStyle(color: _gold, fontSize: 12),
            ),
            style: compact,
          ),
          if (_dayBlockId == null)
            TextButton.icon(
              onPressed: _openBlockDayDialog,
              icon: const Icon(Icons.block, color: _red, size: 14),
              label: const Text(
                'Bloquear dia',
                style: TextStyle(color: _red, fontSize: 12),
              ),
              style: compact,
            ),
          TextButton.icon(
            onPressed: () => setState(() {
              _selectMode = true;
              _selectedLabels.clear();
            }),
            icon: const Icon(Icons.checklist_rounded, color: _muted, size: 16),
            label: const Text(
              'Selecionar',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            style: compact,
          ),
        ],
      );
    }

    final allSelected = _selectedLabels.length == _slots.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0808),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          // Selecionar tudo
          GestureDetector(
            onTap: () => setState(() {
              if (allSelected) {
                _selectedLabels.clear();
              } else {
                _selectedLabels.addAll(_slots.map((s) => s.label));
              }
            }),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allSelected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: _gold,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  allSelected ? 'Desmarcar tudo' : 'Selecionar tudo',
                  style: const TextStyle(color: _gold, fontSize: 12),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Cancelar selecionados
          if (_selectedLabels.isNotEmpty)
            GestureDetector(
              onTap: () async {
                final slots = _selectedLabels
                    .map(
                      (l) => _slots.firstWhere(
                        (s) => s.label == l,
                        orElse: () => _Slot(l),
                      ),
                    )
                    .toList();
                final booked = slots
                    .where(
                      (s) =>
                          s.state == _SlotState.client ||
                          s.state == _SlotState.newClient ||
                          s.state == _SlotState.admin,
                    )
                    .length;
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: _card,
                    title: const Text(
                      'Cancelar horários selecionados?',
                      style: TextStyle(color: _text),
                    ),
                    content: Text(
                      '$booked agendamento(s) serão cancelados. Os horários ficam livres para novos agendamentos.',
                      style: const TextStyle(color: _muted),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text(
                          'Não',
                          style: TextStyle(color: _muted),
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Confirmar'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _cancelAndBlock(slots);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Cancelar (${_selectedLabels.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Sair do modo seleção
          GestureDetector(
            onTap: () => setState(() {
              _selectMode = false;
              _selectedLabels.clear();
            }),
            child: const Text(
              'Sair',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
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

    final barberName =
        widget.barbers
            .firstWhere(
              (b) => b['id']?.toString() == widget.barberId,
              orElse: () => const {'name': ''},
            )['name']
            ?.toString() ??
        '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _legend(),
        const SizedBox(height: 8),
        // ── Banner de dia bloqueado ──────────────────────────────────────
        if (_dayBlockId != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2A0A0A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _red.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.block, color: _red, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Barbeiro bloqueado neste dia — clientes não conseguem agendar.',
                    style: TextStyle(color: _red, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: _card,
                        title: const Text(
                          'Remover bloqueio?',
                          style: TextStyle(color: _text),
                        ),
                        content: const Text(
                          'O barbeiro voltará a aparecer disponível para os clientes neste dia.',
                          style: TextStyle(color: _muted),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text(
                              'Não',
                              style: TextStyle(color: _muted),
                            ),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Remover'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) await _unblockDay();
                  },
                  child: const Text(
                    'Desbloquear',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _selectBar(),
        const SizedBox(height: 8),
        if (barberName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              '$barberName • ${DateFormat("EEEE, dd/MM", 'pt_BR').format(widget.date)}',
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        if (_slots.isEmpty)
          _box(
            'Sem expediente para este dia. Use "Adicionar horário" '
            'para encaixar um atendimento.',
          )
        else
          ..._slots.map(_slotRow),
      ],
    );
  }

  Widget _slotRow(_Slot slot) {
    final fg = _fgFor(slot.state);
    final booked =
        slot.state == _SlotState.client ||
        slot.state == _SlotState.newClient ||
        slot.state == _SlotState.admin;
    final isSelected = _selectMode && _selectedLabels.contains(slot.label);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _selectMode
              ? () => _toggleSelect(slot)
              : () => _onTapSlot(slot),
          child: Container(
            decoration: BoxDecoration(
              color: _bgFor(slot.state),
              borderRadius: BorderRadius.circular(10),
              border: isSelected ? Border.all(color: _red, width: 2.5) : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                // Checkbox no modo seleção
                if (_selectMode) ...[
                  Icon(
                    isSelected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: isSelected ? _red : fg.withValues(alpha: 0.5),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                ],
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
                if (!_selectMode) ...[
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
