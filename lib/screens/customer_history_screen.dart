import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/services/whatsapp_service.dart';

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  final _phoneFormatter = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {'#': RegExp(r'[0-9]')},
  );

  bool _askedForPhone = false;
  bool _loading = false;
  String? _phone;
  String? _error;
  int? _expandedIndex;

  // Each entry = one "booking session" (may span multiple DB rows / blocks)
  List<Map<String, dynamic>> _bookings = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_askedForPhone) {
        _askedForPhone = true;
        _showPhoneDialog();
      }
    });
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _showPhoneDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          _PhoneLookupDialog(formatter: _phoneFormatter, initial: _phone),
    );
    if (!mounted || result == null) return;
    if (_digits(result).length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um telefone válido.')),
      );
      return;
    }
    await _loadHistory(result);
  }

  Future<void> _loadHistory(String phone) async {
    setState(() {
      _loading = true;
      _error = null;
      _phone = phone;
      _expandedIndex = null;
    });
    try {
      final rows = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final candidate in _phoneCandidates(phone)) {
        final response = await Supabase.instance.client
            .from('appointments')
            .select('''
              id, barber_id, service_id,
              appointment_date, appointment_time,
              status, customer_name, customer_phone,
              notes, total_price, created_at, updated_at,
              barbers:barber_id(name, phone),
              services:service_id(name, price)
            ''')
            .eq('customer_phone', candidate)
            .order('appointment_date', ascending: false)
            .order('appointment_time', ascending: false);

        for (final item in response as List) {
          final map = Map<String, dynamic>.from(item as Map);
          final id = map['id']?.toString() ?? '';
          if (id.isNotEmpty && seen.add(id)) rows.add(map);
        }
      }

      rows.sort(
        (a, b) => _appointmentDateTime(b).compareTo(_appointmentDateTime(a)),
      );

      if (!mounted) return;
      setState(() {
        _bookings = _groupIntoBookings(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao buscar histórico: $e';
        _bookings = const [];
        _loading = false;
      });
    }
  }

  // ── Grouping: consecutive blocks → one booking card ───────────────────────────

  List<Map<String, dynamic>> _groupIntoBookings(
    List<Map<String, dynamic>> rows,
  ) {
    // Sort ascending to detect consecutive 30-min slots
    final sorted = List<Map<String, dynamic>>.from(rows)
      ..sort(
        (a, b) => _appointmentDateTime(a).compareTo(_appointmentDateTime(b)),
      );

    final bookings = <Map<String, dynamic>>[];

    for (final row in sorted) {
      final phone    = row['customer_phone']?.toString() ?? '';
      final barberId = row['barber_id']?.toString() ?? '';
      final date     = row['appointment_date']?.toString() ?? '';
      final status   = row['status']?.toString() ?? '';
      final rowDt    = _appointmentDateTime(row);

      // Try to extend an existing booking group
      Map<String, dynamic>? match;
      for (final b in bookings) {
        if (b['_g_phone']    == phone    &&
            b['_g_barberId'] == barberId &&
            b['_g_date']     == date     &&
            b['_g_status']   == status) {
          final lastDt = b['_g_lastDt'] as DateTime;
          if (rowDt.difference(lastDt).inMinutes == 30) {
            match = b;
            break;
          }
        }
      }

      if (match != null) {
        (match['_g_ids'] as List<String>).add(row['id'].toString());
        match['_g_lastDt'] = rowDt;
        match['_g_blocks'] = (match['_g_blocks'] as int) + 1;
        // Accumulate price (extra blocks usually have 0 price)
        final prev = (match['total_price'] as num?)?.toDouble() ?? 0.0;
        final cur  = (row['total_price']   as num?)?.toDouble() ?? 0.0;
        match['total_price'] = prev + cur;
        // Collect unique service names
        final svcSet = match['_g_services'] as Set<String>;
        final svcName = _serviceName(row);
        if (svcName.isNotEmpty) svcSet.add(svcName);
      } else {
        bookings.add({
          ...row,
          '_g_ids':      <String>[row['id'].toString()],
          '_g_phone':    phone,
          '_g_barberId': barberId,
          '_g_date':     date,
          '_g_status':   status,
          '_g_lastDt':   rowDt,
          '_g_blocks':   1,
          '_g_services': <String>{_serviceName(row)},
        });
      }
    }

    // Sort descending again for display (newest first)
    bookings.sort(
      (a, b) => _appointmentDateTime(b).compareTo(_appointmentDateTime(a)),
    );
    return bookings;
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<bool> _cancelGroup(List<String> ids) async {
    final phone = _phone;
    if (phone == null || ids.isEmpty) return false;
    setState(() => _loading = true);
    try {
      // RPC com SECURITY DEFINER — único jeito de contornar o RLS para anon
      for (final id in ids) {
        await Supabase.instance.client.rpc(
          'set_customer_appointment_status',
          params: {
            'p_appointment_id': id,
            'p_phone': phone,
            'p_status': 'cancelled',
          },
        );
      }
      await _loadHistory(phone);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível cancelar: $e')),
      );
      return false;
    }
  }

  Future<void> _cancelAndNotify(Map<String, dynamic> booking) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _P.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _P.stroke),
        ),
        title: const Text(
          'Cancelar agendamento?',
          style: TextStyle(color: _P.text),
        ),
        content: const Text(
          'Esta ação não pode ser desfeita.',
          style: TextStyle(color: _P.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar', style: TextStyle(color: _P.muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _P.danger),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Captura os dados antes do async
    final allIds  = (booking['_g_ids'] as List<String>?) ?? [booking['id'].toString()];
    final cliente = booking['customer_name']?.toString() ?? 'Cliente';
    final clientPhone = booking['customer_phone']?.toString() ?? '';
    final dt      = _appointmentDateTime(booking);
    final dateStr = DateFormat('dd/MM/yyyy', 'pt_BR').format(dt);
    final timeStr = DateFormat('HH:mm').format(dt);
    final servico = _bookingServiceLabel(booking);
    final barberPhone = (booking['barbers'] is Map)
        ? (booking['barbers']['phone']?.toString() ?? '')
        : '';

    // Cancela todos os blocos de uma vez → libera a agenda do barbeiro
    final ok = await _cancelGroup(allIds);
    if (!ok) return;

    // Notifica cliente E barbeiro via WhatsApp (fire and forget)
    WhatsappService.loadConfig().then((config) {
      if (!config.enabled || !config.isConfigured) return;

      // Mensagem para o cliente
      if (clientPhone.isNotEmpty) {
        final msgCliente = '❌ *Agendamento cancelado*\n\n'
            'Olá, $cliente! Seu agendamento foi cancelado:\n\n'
            '📅 Data: $dateStr\n'
            '🕐 Hora: $timeStr\n'
            '✂️ Serviço: $servico\n\n'
            'Para reagendar acesse nosso app. 😊';
        WhatsappService.sendMessage(
            phone: clientPhone, message: msgCliente, config: config);
      }

      // Mensagem para o barbeiro
      if (barberPhone.isNotEmpty) {
        final msgBarbeiro = '❌ *Agendamento cancelado pelo cliente*\n\n'
            '👤 Cliente: $cliente\n'
            '📅 Data: $dateStr\n'
            '🕐 Hora: $timeStr\n'
            '✂️ Serviço: $servico\n\n'
            'O horário foi liberado na sua agenda.';
        WhatsappService.sendMessage(
            phone: barberPhone, message: msgBarbeiro, config: config);
      }
    });
  }

  Future<void> _rescheduleAppointment(Map<String, dynamic> booking) async {
    if (!mounted) return;
    final rescheduled = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RescheduleModal(appointment: booking),
    );
    if (!mounted || rescheduled != true) return;
    final phone = _phone;
    if (phone != null) await _loadHistory(phone);
  }

  Future<void> _refresh() async {
    final phone = _phone;
    if (phone == null) {
      await _showPhoneDialog();
      return;
    }
    await _loadHistory(phone);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final hPad  = width > 600 ? (width - 560) / 2 : 0.0;

    final customerName = _bookings.isEmpty
        ? null
        : _bookings.first['customer_name']?.toString().trim();

    return Scaffold(
      backgroundColor: _P.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _P.gold,
          backgroundColor: _P.panel,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(18 + hPad, 18, 18 + hPad, 0),
                  child: _HistoryHeader(
                    customerName:
                        customerName == null || customerName.isEmpty
                            ? null
                            : customerName,
                    phone: _phone,
                    count: _bookings.length,
                    onChangePhone: _showPhoneDialog,
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: _P.gold),
                  ),
                )
              else if (_phone == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyHistory(
                    icon: Icons.phone_iphone_rounded,
                    title: 'Consulte pelo telefone',
                    subtitle:
                        'Use o celular informado no agendamento para carregar os horários.',
                    actionLabel: 'Informar telefone',
                    onAction: _showPhoneDialog,
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyHistory(
                    icon: Icons.error_outline_rounded,
                    title: 'Não foi possível carregar',
                    subtitle: _error!,
                    actionLabel: 'Tentar novamente',
                    onAction: _refresh,
                  ),
                )
              else if (_bookings.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyHistory(
                    icon: Icons.event_busy_rounded,
                    title: 'Nenhum agendamento encontrado',
                    subtitle:
                        'Confira o telefone informado ou consulte outro número.',
                    actionLabel: 'Trocar telefone',
                    onAction: _showPhoneDialog,
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    14 + hPad, 0, 14 + hPad, 100,
                  ),
                  sliver: SliverList.builder(
                    itemCount: _bookings.length,
                    itemBuilder: (context, index) {
                      final booking  = _bookings[index];
                      final previous = index == 0 ? null : _bookings[index - 1];
                      final showDay  =
                          previous == null ||
                          _dayKey(previous) != _dayKey(booking);
                      final expanded = _expandedIndex == index;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDay)
                            _DaySeparator(label: _dayLabel(booking)),
                          _AppointmentCard(
                            booking: booking,
                            expanded: expanded,
                            onTap: () => setState(() {
                              _expandedIndex = expanded ? null : index;
                            }),
                            onCancel: () => _cancelAndNotify(booking),
                            onReschedule: () => _rescheduleAppointment(booking),
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Phone lookup dialog ───────────────────────────────────────────────────────

class _PhoneLookupDialog extends StatefulWidget {
  const _PhoneLookupDialog({required this.formatter, required this.initial});

  final MaskTextInputFormatter formatter;
  final String? initial;

  @override
  State<_PhoneLookupDialog> createState() => _PhoneLookupDialogState();
}

class _PhoneLookupDialogState extends State<_PhoneLookupDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _P.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _P.stroke),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _DialogIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Buscar histórico',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _P.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Celular usado no agendamento',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _P.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                inputFormatters: [widget.formatter],
                style: const TextStyle(color: _P.text),
                cursorColor: _P.gold,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '(00) 00000-0000',
                  hintStyle: const TextStyle(color: _P.muted),
                  errorText: _error,
                  prefixIcon:
                      const Icon(Icons.phone_rounded, color: _P.gold),
                  filled: true,
                  fillColor: _P.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _P.stroke),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _P.stroke),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _P.gold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _P.muted,
                        side: const BorderSide(color: _P.stroke),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Agora não'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _P.gold,
                        foregroundColor: _P.bg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Consultar',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final phone = _controller.text.trim();
    if (_digits(phone).length < 10) {
      setState(() => _error = 'Telefone incompleto');
      return;
    }
    Navigator.of(context).pop(phone);
  }
}

class _DialogIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _P.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.manage_search_rounded, color: _P.gold),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.customerName,
    required this.phone,
    required this.count,
    required this.onChangePhone,
  });

  final String? customerName;
  final String? phone;
  final int count;
  final VoidCallback onChangePhone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Histórico',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _P.text,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Trocar telefone',
              onPressed: onChangePhone,
              icon: const Icon(Icons.phone_forwarded_rounded, color: _P.gold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          customerName == null
              ? 'Consulte os horários pelo celular do cliente.'
              : 'Agendamentos de $customerName',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: _P.muted),
        ),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _P.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _P.stroke),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.fact_check_outlined, color: _P.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phone ?? 'Telefone não informado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: _P.text,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$count agendamento${count == 1 ? '' : 's'} encontrado${count == 1 ? '' : 's'}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: _P.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onChangePhone,
                  style: TextButton.styleFrom(foregroundColor: _P.gold),
                  child: const Text('Alterar'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

// ── Day separator ─────────────────────────────────────────────────────────────

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: _P.gold,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Appointment card ──────────────────────────────────────────────────────────

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.booking,
    required this.expanded,
    required this.onTap,
    required this.onCancel,
    required this.onReschedule,
  });

  final Map<String, dynamic> booking;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context) {
    final status   = _statusInfo(booking['status']?.toString());
    final dateTime = _appointmentDateTime(booking);
    final blocks   = booking['_g_blocks'] as int? ?? 1;

    final canCancel =
        status.raw != 'cancelled' &&
        status.raw != 'canceled'  &&
        status.raw != 'completed' &&
        status.raw != 'attended'  &&
        status.raw != 'no_show';

    // Time label: "13:00" for 1 block, "13:00 – 14:30" for multi-block
    final startLabel = DateFormat('HH:mm').format(dateTime);
    final timeLabel  = blocks > 1
        ? '$startLabel – ${DateFormat('HH:mm').format(dateTime.add(Duration(minutes: 30 * blocks)))}'
        : startLabel;

    // Duration badge
    final durationMins = blocks * 30;
    final durationLabel = durationMins < 60
        ? '${durationMins}min'
        : durationMins % 60 == 0
            ? '${durationMins ~/ 60}h'
            : '${durationMins ~/ 60}h${(durationMins % 60).toString().padLeft(2, '0')}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _P.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _P.stroke),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status accent bar
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: status.color,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(10),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row: status pill + time
                        Row(
                          children: [
                            _StatusPill(status: status),
                            const Spacer(),
                            Text(
                              timeLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: _P.gold,
                                    fontWeight: FontWeight.w900,
                                    fontSize: blocks > 1 ? 12 : 14,
                                  ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Service name
                        Text(
                          _bookingServiceLabel(booking),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: _P.text,
                                fontWeight: FontWeight.w900,
                              ),
                        ),

                        const SizedBox(height: 6),

                        _DetailLine(
                          icon: Icons.person_rounded,
                          text: _barberName(booking),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _DetailLine(
                                icon: Icons.attach_money_rounded,
                                text: _priceLabel(booking),
                              ),
                            ),
                            if (blocks > 1)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _P.gold.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _P.gold.withValues(alpha: 0.30),
                                  ),
                                ),
                                child: Text(
                                  durationLabel,
                                  style: const TextStyle(
                                    color: _P.gold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        // Expanded details
                        if (expanded) ...[
                          const Divider(color: _P.stroke, height: 22),
                          _DetailLine(
                            icon: Icons.calendar_month_rounded,
                            text: DateFormat(
                              "EEEE, dd/MM/yyyy 'às' HH:mm",
                              'pt_BR',
                            ).format(dateTime),
                          ),
                          _DetailLine(
                            icon: Icons.receipt_long_rounded,
                            text:
                                'Código ${booking['id']?.toString().substring(0, 8) ?? '-'}',
                          ),
                          if (canCancel) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: onReschedule,
                              icon: const Icon(
                                Icons.event_repeat_rounded,
                                size: 17,
                              ),
                              label: const Text(
                                'Remarcar agendamento',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _P.gold,
                                foregroundColor: _P.bg,
                                minimumSize:
                                    const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: onCancel,
                              icon: const Icon(
                                Icons.cancel_outlined,
                                size: 17,
                              ),
                              label: const Text(
                                'Cancelar agendamento',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _P.danger,
                                backgroundColor:
                                    _P.danger.withValues(alpha: 0.10),
                                side: const BorderSide(
                                  color: _P.danger,
                                  width: 1.5,
                                ),
                                minimumSize:
                                    const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final _StatusInfo status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, color: status.color, size: 14),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: status.color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, color: _P.gold, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _P.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _P.gold, size: 42),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _P.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: _P.muted),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: _P.gold,
                foregroundColor: _P.bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reschedule bottom sheet ───────────────────────────────────────────────────

class _RescheduleModal extends StatefulWidget {
  const _RescheduleModal({required this.appointment});
  final Map<String, dynamic> appointment;

  @override
  State<_RescheduleModal> createState() => _RescheduleModalState();
}

class _RescheduleModalState extends State<_RescheduleModal> {
  DateTime?       _selectedDate;
  TimeOfDay?      _selectedTime;
  DateTime?       _selectedDateTime;
  List<TimeOfDay> _availableSlots = const [];
  Set<String>     _takenSlots     = const {};
  bool _loadingSlots = false;
  bool _saving       = false;

  Map<String, dynamic> get _ap => widget.appointment;
  String get _barberId      => _ap['barber_id']?.toString()      ?? '';
  String get _serviceId     => _ap['service_id']?.toString()     ?? '';
  String get _customerName  => _ap['customer_name']?.toString()  ?? '';
  String get _customerPhone => _ap['customer_phone']?.toString() ?? '';
  double get _totalPrice    => (_ap['total_price'] as num?)?.toDouble() ?? 0;

  List<String> get _allIds =>
      (_ap['_g_ids'] as List<String>?) ?? [_ap['id'].toString()];

  String get _barberNameStr {
    final b = _ap['barbers'];
    return (b is Map ? b['name'] : null)?.toString() ?? '—';
  }

  String get _serviceNameStr {
    final s = _ap['services'];
    return (s is Map ? s['name'] : null)?.toString() ?? '—';
  }

  Future<void> _loadSlots(DateTime date) async {
    setState(() {
      _loadingSlots = true;
      _selectedTime = null;
      _selectedDateTime = null;
    });
    try {
      final dow    = date.weekday;
      final avRows = await Supabase.instance.client
          .from('barber_availability')
          .select('*')
          .eq('barber_id', _barberId)
          .eq('day_of_week', dow == 7 ? 0 : dow)
          .limit(1);

      TimeOfDay start = const TimeOfDay(hour: 9,  minute: 0);
      TimeOfDay end   = const TimeOfDay(hour: 18, minute: 0);
      bool enabled    = true;
      if (avRows.isNotEmpty) {
        final row = avRows.first;
        enabled = (row['is_available'] ?? true) == true;
        final st = '${row['start_time'] ?? '09:00'}'.split(':');
        final et = '${row['end_time']   ?? '18:00'}'.split(':');
        start = TimeOfDay(
          hour: int.tryParse(st[0]) ?? 9,
          minute: int.tryParse(st[1]) ?? 0,
        );
        end = TimeOfDay(
          hour: int.tryParse(et[0]) ?? 18,
          minute: int.tryParse(et[1]) ?? 0,
        );
      }

      final slots = <TimeOfDay>[];
      if (enabled) {
        var cur     = DateTime(date.year, date.month, date.day, start.hour, start.minute);
        final endDt = DateTime(date.year, date.month, date.day, end.hour,   end.minute);
        while (cur.isBefore(endDt) || cur.isAtSameMomentAs(endDt)) {
          slots.add(TimeOfDay(hour: cur.hour, minute: cur.minute));
          cur = cur.add(const Duration(minutes: 30));
        }
      }

      final dateStr   = DateFormat('yyyy-MM-dd').format(date);
      final takenRows = await Supabase.instance.client
          .from('appointments')
          .select('id, appointment_time, status')
          .eq('barber_id', _barberId)
          .eq('appointment_date', dateStr);

      final taken = <String>{};
      for (final r in takenRows as List) {
        final m  = r as Map<String, dynamic>;
        if (_allIds.contains(m['id']?.toString())) continue;
        final st = m['status']?.toString() ?? '';
        if (st == 'cancelled' || st == 'canceled' || st == 'no_show') continue;
        final parts = (m['appointment_time']?.toString() ?? '').split(':');
        if (parts.length >= 2) {
          taken.add(
            '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}',
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _availableSlots = slots;
        _takenSlots     = taken;
        _loadingSlots   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _confirm() async {
    final dt = _selectedDateTime;
    if (dt == null) return;
    setState(() => _saving = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(dt);
      final timeStr = '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:00';

      await Supabase.instance.client.from('appointments').insert({
        'service_id':       _serviceId,
        'barber_id':        _barberId,
        'appointment_date': dateStr,
        'appointment_time': timeStr,
        'status':           'scheduled',
        'customer_name':    _customerName,
        'customer_phone':   _customerPhone,
        'notes':            'Reagendamento — $_customerName / $_customerPhone',
        'total_price':      _totalPrice,
      });

      // Cancel all old blocks via SECURITY DEFINER RPC (contorna RLS para anon)
      for (final id in _allIds) {
        await Supabase.instance.client.rpc(
          'set_customer_appointment_status',
          params: {
            'p_appointment_id': id,
            'p_phone': _customerPhone,
            'p_status': 'cancelled',
          },
        );
      }

      // WhatsApp notification
      final dateF   = DateFormat('dd/MM/yyyy', 'pt_BR').format(dt);
      final timeF   = DateFormat('HH:mm').format(dt);
      WhatsappService.loadConfig().then((config) {
        if (!config.enabled || !config.isConfigured) return;
        final msg = '🔄 *Agendamento remarcado!*\n\n'
            'Olá, $_customerName! Seu novo horário está confirmado:\n\n'
            '📅 Data: $dateF\n'
            '🕐 Hora: $timeF\n'
            '✂️ Serviço: $_serviceNameStr\n'
            '💈 Profissional: $_barberNameStr\n\n'
            'Te esperamos! 😊';
        WhatsappService.sendMessage(
          phone: _customerPhone, message: msg, config: config);
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao remarcar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: _P.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: _P.stroke)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: _P.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Remarcar agendamento',
              style: TextStyle(
                color: _P.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$_serviceNameStr  •  $_barberNameStr',
              style: const TextStyle(color: _P.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: () async {
                final now    = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  locale: const Locale('pt', 'BR'),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 60)),
                  initialDate: now,
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: Theme.of(ctx).colorScheme.copyWith(
                        primary:   _P.gold,
                        onPrimary: _P.bg,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked == null || !mounted) return;
                final date = DateTime(picked.year, picked.month, picked.day);
                setState(() => _selectedDate = date);
                await _loadSlots(date);
              },
              icon: const Icon(
                Icons.calendar_today_outlined,
                size: 16, color: _P.gold,
              ),
              label: Text(
                _selectedDate == null
                    ? 'Selecionar nova data'
                    : DateFormat('EEEE, dd/MM/yyyy', 'pt_BR')
                        .format(_selectedDate!),
                style: const TextStyle(color: _P.gold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _P.gold),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (_loadingSlots)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(color: _P.gold),
                ),
              )
            else if (_selectedDate != null && _availableSlots.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nenhum horário disponível neste dia.',
                  style: TextStyle(color: _P.muted),
                ),
              )
            else if (_availableSlots.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableSlots.map((t) {
                  final label    = '${t.hour.toString().padLeft(2, '0')}:'
                      '${t.minute.toString().padLeft(2, '0')}';
                  final taken    = _takenSlots.contains(label);
                  final selected = _selectedTime == t;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    selectedColor: _P.gold,
                    backgroundColor: _P.card,
                    disabledColor: _P.card.withValues(alpha: 0.4),
                    side: BorderSide(
                      color: selected ? _P.gold : _P.stroke,
                    ),
                    labelStyle: TextStyle(
                      color: selected ? _P.bg : taken ? _P.muted : _P.text,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                    onSelected: taken
                        ? null
                        : (v) {
                            if (!v) return;
                            setState(() {
                              _selectedTime = t;
                              _selectedDateTime = DateTime(
                                _selectedDate!.year,
                                _selectedDate!.month,
                                _selectedDate!.day,
                                t.hour, t.minute,
                              );
                            });
                          },
                  );
                }).toList(),
              ),

            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: (_selectedDateTime == null || _saving) ? null : _confirm,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: _P.bg,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_saving ? 'Remarcando...' : 'Confirmar remarcação'),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _selectedDateTime != null ? _P.gold : _P.stroke,
                foregroundColor: _P.bg,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

List<String> _phoneCandidates(String phone) {
  final digits = _digits(phone);
  final values = <String>{phone.trim(), digits};
  if (digits.length == 11) {
    values.add(
      '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}',
    );
  } else if (digits.length == 10) {
    values.add(
      '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}',
    );
  }
  values.removeWhere((v) => v.isEmpty);
  return values.toList();
}

DateTime _appointmentDateTime(Map<String, dynamic> appt) {
  final date = appt['appointment_date']?.toString() ?? '';
  final time = appt['appointment_time']?.toString() ?? '00:00:00';
  if (date.isNotEmpty) {
    return DateTime.tryParse('$date $time') ??
        DateTime.tryParse('${date}T$time') ??
        DateTime.now();
  }
  return DateTime.tryParse(appt['created_at']?.toString() ?? '') ??
      DateTime.now();
}

String _dayKey(Map<String, dynamic> appt) =>
    DateFormat('yyyy-MM-dd').format(_appointmentDateTime(appt));

String _dayLabel(Map<String, dynamic> appt) =>
    DateFormat('EEEE, dd/MM', 'pt_BR').format(_appointmentDateTime(appt));

String _serviceName(Map<String, dynamic> appt) {
  final s = appt['services'];
  if (s is Map && s['name'] != null) return s['name'].toString();
  return 'Serviço';
}

String _bookingServiceLabel(Map<String, dynamic> booking) {
  final names = booking['_g_services'] as Set<String>?;
  if (names != null && names.length > 1) return names.join(' + ');
  return _serviceName(booking);
}

String _barberName(Map<String, dynamic> appt) {
  final b = appt['barbers'];
  if (b is Map && b['name'] != null) return 'Profissional ${b['name']}';
  return 'Profissional não informado';
}

String _priceLabel(Map<String, dynamic> appt) {
  final raw =
      appt['total_price'] ??
      ((appt['services'] is Map) ? (appt['services'] as Map)['price'] : null);
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
  return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
}

_StatusInfo _statusInfo(String? rawStatus) {
  final raw = (rawStatus ?? 'scheduled').trim().toLowerCase();
  switch (raw) {
    case 'confirmed':
      return const _StatusInfo(
        'confirmed', 'Confirmado',
        Icons.check_circle_rounded, _P.success,
      );
    case 'cancelled':
    case 'canceled':
      return const _StatusInfo(
        'cancelled', 'Cancelado',
        Icons.cancel_rounded, _P.danger,
      );
    case 'completed':
    case 'attended':
      return const _StatusInfo(
        'completed', 'Concluído',
        Icons.task_alt_rounded, _P.mint,
      );
    case 'no_show':
      return const _StatusInfo(
        'no_show', 'Ausente',
        Icons.person_off_rounded, _P.muted,
      );
    case 'pending':
      return const _StatusInfo(
        'pending', 'Pendente',
        Icons.schedule_rounded, _P.gold,
      );
    default:
      return const _StatusInfo(
        'scheduled', 'Agendado',
        Icons.event_available_rounded, _P.gold,
      );
  }
}

class _StatusInfo {
  const _StatusInfo(this.raw, this.label, this.icon, this.color);

  final String raw;
  final String label;
  final IconData icon;
  final Color color;
}

// ── Palette — matches the dark admin/booking theme ────────────────────────────

class _P {
  static const Color bg      = Color(0xFF080808);
  static const Color panel   = Color(0xFF111111);
  static const Color card    = Color(0xFF111111);
  static const Color stroke  = Color(0xFF222222);
  static const Color text    = Color(0xFFF0EDE8);
  static const Color muted   = Color(0xFF6B7280);
  static const Color gold    = Color(0xFFF5C200);
  static const Color mint    = Color(0xFF20D8B2);
  static const Color danger  = Color(0xFFE85B4D);
  static const Color success = Color(0xFF4CAF50);
}
