import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<Map<String, dynamic>> _appointments = const [];

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

  Future<void> _showPhoneDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return _PhoneLookupDialog(formatter: _phoneFormatter, initial: _phone);
      },
    );

    if (!mounted || result == null) return;
    final digits = _digits(result);
    if (digits.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um telefone valido.')),
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
              id,
              barber_id,
              service_id,
              appointment_date,
              appointment_time,
              status,
              customer_name,
              customer_phone,
              notes,
              total_price,
              created_at,
              updated_at,
              barbers:barber_id(name),
              services:service_id(name, price)
            ''')
            .eq('customer_phone', candidate)
            .order('appointment_date', ascending: false)
            .order('appointment_time', ascending: false);

        for (final item in response as List) {
          final map = Map<String, dynamic>.from(item as Map);
          final id = map['id']?.toString() ?? '';
          if (id.isNotEmpty && seen.add(id)) {
            rows.add(map);
          }
        }
      }

      rows.sort(
        (a, b) => _appointmentDateTime(b).compareTo(_appointmentDateTime(a)),
      );

      if (!mounted) return;
      setState(() {
        _appointments = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao buscar historico: $e';
        _appointments = const [];
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(
    Map<String, dynamic> appointment,
    String status,
  ) async {
    final phone = _phone;
    final id = appointment['id']?.toString();
    if (phone == null || id == null || id.isEmpty) return;

    setState(() => _loading = true);
    try {
      var updated = false;
      try {
        await Supabase.instance.client.rpc(
          'set_customer_appointment_status',
          params: {
            'p_appointment_id': id,
            'p_phone': phone,
            'p_status': status,
          },
        );
        updated = true;
      } catch (_) {
        final response = await Supabase.instance.client
            .from('appointments')
            .update({'status': status})
            .eq('id', id)
            .inFilter('customer_phone', _phoneCandidates(phone))
            .select('id');
        updated = response.isNotEmpty;
      }

      if (!updated) {
        throw Exception('nenhum agendamento foi atualizado');
      }

      await _loadHistory(phone);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Nao foi possivel atualizar: $e')));
    }
  }

  Future<void> _refresh() async {
    final phone = _phone;
    if (phone == null) {
      await _showPhoneDialog();
      return;
    }
    await _loadHistory(phone);
  }

  @override
  Widget build(BuildContext context) {
    final customerName = _appointments.isEmpty
        ? null
        : (_appointments.first['customer_name']?.toString().trim());

    return Scaffold(
      backgroundColor: _HistoryPalette.frame,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: _HistoryPalette.bg),
              child: RefreshIndicator(
                color: _HistoryPalette.gold,
                backgroundColor: _HistoryPalette.bg,
                onRefresh: _refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _HistoryHeader(
                        customerName:
                            customerName == null || customerName.isEmpty
                            ? _phone
                            : customerName,
                        onChangePhone: _showPhoneDialog,
                      ),
                    ),
                    if (_loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: _HistoryPalette.gold,
                          ),
                        ),
                      )
                    else if (_phone == null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyHistory(
                          icon: Icons.phone_iphone_rounded,
                          title: 'Informe seu telefone',
                          subtitle:
                              'Digite o celular usado no agendamento para ver o historico.',
                          actionLabel: 'Buscar historico',
                          onAction: _showPhoneDialog,
                        ),
                      )
                    else if (_error != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyHistory(
                          icon: Icons.error_outline_rounded,
                          title: 'Nao foi possivel carregar',
                          subtitle: _error!,
                          actionLabel: 'Tentar novamente',
                          onAction: _refresh,
                        ),
                      )
                    else if (_appointments.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyHistory(
                          icon: Icons.event_busy_rounded,
                          title: 'Nenhum agendamento encontrado',
                          subtitle:
                              'Confira o telefone informado e tente novamente.',
                          actionLabel: 'Trocar telefone',
                          onAction: _showPhoneDialog,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                        sliver: SliverList.builder(
                          itemCount: _appointments.length,
                          itemBuilder: (context, index) {
                            final appointment = _appointments[index];
                            final previous = index == 0
                                ? null
                                : _appointments[index - 1];
                            final showMonth =
                                previous == null ||
                                _monthLabel(previous) !=
                                    _monthLabel(appointment);
                            final expanded = _expandedIndex == index;

                            return _TimelineAppointmentCard(
                              appointment: appointment,
                              showMonth: showMonth,
                              monthLabel: _monthLabel(appointment),
                              dateLabel: _shortDateLabel(appointment),
                              expanded: expanded,
                              onTap: () {
                                setState(() {
                                  _expandedIndex = expanded ? null : index;
                                });
                              },
                              onCancel: () =>
                                  _updateStatus(appointment, 'cancelled'),
                              onConfirm: () =>
                                  _updateStatus(appointment, 'confirmed'),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
      insetPadding: const EdgeInsets.symmetric(horizontal: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HistoryPalette.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _HistoryPalette.gold, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Insira seu numero de telefone:',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _HistoryPalette.gold,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                inputFormatters: [widget.formatter],
                textAlign: TextAlign.center,
                style: const TextStyle(color: _HistoryPalette.gold),
                cursorColor: _HistoryPalette.gold,
                decoration: InputDecoration(
                  hintText: '(DDD)00000-0000',
                  hintStyle: TextStyle(
                    color: _HistoryPalette.gold.withValues(alpha: 0.45),
                  ),
                  errorText: _error,
                  errorStyle: const TextStyle(color: _HistoryPalette.danger),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: _HistoryPalette.gold),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(
                      color: _HistoryPalette.gold,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: () {
                  final phone = _controller.text.trim();
                  if (_digits(phone).length < 10) {
                    setState(() {
                      _error = 'Telefone incompleto';
                    });
                    return;
                  }
                  Navigator.of(context).pop(phone);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _HistoryPalette.gold,
                  side: const BorderSide(color: _HistoryPalette.gold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.customerName,
    required this.onChangePhone,
  });

  final String? customerName;
  final VoidCallback onChangePhone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AGENDA SERVICO',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _HistoryPalette.mint,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Trocar telefone',
                onPressed: onChangePhone,
                icon: const Icon(
                  Icons.logout_rounded,
                  color: _HistoryPalette.mint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              _SmallSealLogo(),
              Spacer(),
              Icon(Icons.map_rounded, color: _HistoryPalette.gold, size: 34),
              SizedBox(width: 28),
              Icon(
                Icons.photo_camera_outlined,
                color: _HistoryPalette.gold,
                size: 32,
              ),
              SizedBox(width: 18),
            ],
          ),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Historico de Agendamentos',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _HistoryPalette.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (customerName != null && customerName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                customerName!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: _HistoryPalette.gold),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: _HistoryPalette.gold, height: 1),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _SmallSealLogo extends StatelessWidget {
  const _SmallSealLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      height: 118,
      child: CustomPaint(
        painter: _SmallSealPainter(),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'T',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: _HistoryPalette.gold,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.face_retouching_natural_rounded,
                color: _HistoryPalette.gold,
                size: 32,
              ),
              const SizedBox(width: 6),
              Text(
                'D',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: _HistoryPalette.gold,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallSealPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _HistoryPalette.gold;
    canvas
      ..drawCircle(center, 52, paint)
      ..drawCircle(center, 39, paint..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TimelineAppointmentCard extends StatelessWidget {
  const _TimelineAppointmentCard({
    required this.appointment,
    required this.showMonth,
    required this.monthLabel,
    required this.dateLabel,
    required this.expanded,
    required this.onTap,
    required this.onCancel,
    required this.onConfirm,
  });

  final Map<String, dynamic> appointment;
  final bool showMonth;
  final String monthLabel;
  final String dateLabel;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final status = _statusInfo(appointment['status']?.toString());
    final canConfirm = status.raw == 'scheduled' || status.raw == 'pending';
    final canCancel =
        status.raw != 'cancelled' &&
        status.raw != 'canceled' &&
        status.raw != 'completed' &&
        status.raw != 'attended' &&
        status.raw != 'no_show';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              if (showMonth) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: _HistoryPalette.gold,
                    shape: BoxShape.circle,
                  ),
                ),
              ] else
                const SizedBox(height: 12),
              Container(
                width: 1,
                height: expanded ? 170 : 118,
                color: _HistoryPalette.gold,
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showMonth)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    monthLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _HistoryPalette.gold,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _HistoryPalette.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _AppointmentPanel(
                appointment: appointment,
                expanded: expanded,
                status: status,
                canCancel: canCancel,
                canConfirm: canConfirm,
                onTap: onTap,
                onCancel: onCancel,
                onConfirm: onConfirm,
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppointmentPanel extends StatelessWidget {
  const _AppointmentPanel({
    required this.appointment,
    required this.expanded,
    required this.status,
    required this.canCancel,
    required this.canConfirm,
    required this.onTap,
    required this.onCancel,
    required this.onConfirm,
  });

  final Map<String, dynamic> appointment;
  final bool expanded;
  final _StatusInfo status;
  final bool canCancel;
  final bool canConfirm;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final serviceName = _serviceName(appointment);
    final barberName = _barberName(appointment);
    final dateTime = _appointmentDateTime(appointment);
    final value = _priceLabel(appointment);

    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HistoryPalette.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _HistoryPalette.gold, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: _HistoryPalette.mint.withValues(alpha: 0.65),
              blurRadius: 9,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (expanded) ...[
                Text(
                  '#Agendamento ${status.label}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _HistoryPalette.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _InfoLine(icon: Icons.info_rounded, text: serviceName),
              _InfoLine(
                icon: Icons.calendar_month_rounded,
                text: DateFormat(
                  "EEEE dd/MM 'as' HH:mm",
                  'pt_BR',
                ).format(dateTime),
              ),
              _InfoLine(
                icon: Icons.person_rounded,
                text: 'Profissional $barberName',
              ),
              _InfoLine(icon: Icons.attach_money_rounded, text: value),
              if (expanded) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    _StepBadge(
                      icon: Icons.history_rounded,
                      label: 'Agendamento\nCadastrado',
                      active: true,
                    ),
                    const SizedBox(width: 12),
                    _StepBadge(
                      icon: Icons.check_rounded,
                      label: status.raw == 'confirmed'
                          ? 'Agendamento\nConfirmado'
                          : 'Confirmar\nAgendamento',
                      active: status.raw == 'confirmed',
                    ),
                  ],
                ),
                if (canCancel || canConfirm) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (canCancel)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onCancel,
                            icon: const Icon(Icons.cancel_outlined, size: 16),
                            label: const Text('Cancelar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _HistoryPalette.danger,
                              side: const BorderSide(
                                color: _HistoryPalette.danger,
                              ),
                            ),
                          ),
                        ),
                      if (canCancel && canConfirm) const SizedBox(width: 10),
                      if (canConfirm)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onConfirm,
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Confirmar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _HistoryPalette.success,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: _HistoryPalette.gold, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _HistoryPalette.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _HistoryPalette.bg,
            border: Border.all(
              color: active ? _HistoryPalette.gold : _HistoryPalette.muted,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: _HistoryPalette.gold.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: active ? _HistoryPalette.gold : _HistoryPalette.muted,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: active ? _HistoryPalette.gold : _HistoryPalette.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _HistoryPalette.gold, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _HistoryPalette.gold,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _HistoryPalette.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: _HistoryPalette.gold,
                side: const BorderSide(color: _HistoryPalette.gold),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

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
  values.removeWhere((value) => value.isEmpty);
  return values.toList();
}

DateTime _appointmentDateTime(Map<String, dynamic> appointment) {
  final date = appointment['appointment_date']?.toString() ?? '';
  final time = appointment['appointment_time']?.toString() ?? '00:00:00';
  if (date.isNotEmpty) {
    return DateTime.tryParse('$date $time') ??
        DateTime.tryParse('${date}T$time') ??
        DateTime.now();
  }
  return DateTime.tryParse(appointment['created_at']?.toString() ?? '') ??
      DateTime.now();
}

String _monthLabel(Map<String, dynamic> appointment) {
  final text = DateFormat(
    'MMMM',
    'pt_BR',
  ).format(_appointmentDateTime(appointment));
  return text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}

String _shortDateLabel(Map<String, dynamic> appointment) {
  return DateFormat('dd/MM', 'pt_BR').format(_appointmentDateTime(appointment));
}

String _serviceName(Map<String, dynamic> appointment) {
  final service = appointment['services'];
  if (service is Map && service['name'] != null) {
    return service['name'].toString().toUpperCase();
  }
  return 'SERVICO';
}

String _barberName(Map<String, dynamic> appointment) {
  final barber = appointment['barbers'];
  if (barber is Map && barber['name'] != null) {
    return barber['name'].toString();
  }
  return 'Barbeiro';
}

String _priceLabel(Map<String, dynamic> appointment) {
  final raw =
      appointment['total_price'] ??
      ((appointment['services'] is Map)
          ? (appointment['services'] as Map)['price']
          : null);
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
  return 'Valor ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value)}';
}

_StatusInfo _statusInfo(String? rawStatus) {
  final raw = (rawStatus ?? 'scheduled').trim().toLowerCase();
  switch (raw) {
    case 'confirmed':
      return const _StatusInfo('confirmed', 'Confirmado');
    case 'cancelled':
    case 'canceled':
      return const _StatusInfo('cancelled', 'Cancelado');
    case 'completed':
    case 'attended':
      return const _StatusInfo('completed', 'Concluido');
    case 'no_show':
      return const _StatusInfo('no_show', 'Nao compareceu');
    case 'pending':
      return const _StatusInfo('pending', 'Pendente');
    default:
      return const _StatusInfo('scheduled', 'Cadastrado');
  }
}

class _StatusInfo {
  const _StatusInfo(this.raw, this.label);

  final String raw;
  final String label;
}

class _HistoryPalette {
  static const Color frame = Color(0xFF223C3C);
  static const Color bg = Color(0xFF0D0B0B);
  static const Color card = Color(0xFF111010);
  static const Color gold = Color(0xFFFFD400);
  static const Color mint = Color(0xFF00D8A8);
  static const Color muted = Color(0xFF8E7B3D);
  static const Color danger = Color(0xFFFF4B3E);
  static const Color success = Color(0xFF4CAF50);
}
