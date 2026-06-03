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
    if (_digits(result).length < 10) {
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
          if (id.isNotEmpty && seen.add(id)) rows.add(map);
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

  Future<void> _cancelAndNotify(Map<String, dynamic> appointment) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _HistoryPalette.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _HistoryPalette.stroke),
        ),
        title: const Text(
          'Cancelar agendamento?',
          style: TextStyle(color: _HistoryPalette.text),
        ),
        content: const Text(
          'Esta ação não pode ser desfeita.',
          style: TextStyle(color: _HistoryPalette.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar',
                style: TextStyle(color: _HistoryPalette.muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: _HistoryPalette.danger),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Captura antes do async
    final phone   = appointment['customer_phone']?.toString() ?? '';
    final cliente = appointment['customer_name']?.toString() ?? '';
    final dt      = _appointmentDateTime(appointment);
    final dateStr = DateFormat('dd/MM/yyyy', 'pt_BR').format(dt);
    final timeStr = DateFormat('HH:mm').format(dt);
    final servico = (appointment['services'] is Map)
        ? (appointment['services']['name']?.toString() ?? '')
        : '';

    await _updateStatus(appointment, 'cancelled');

    if (phone.isEmpty) return;
    WhatsappService.loadConfig().then((config) {
      if (!config.enabled || !config.isConfigured) return;
      final msg = '❌ *Agendamento cancelado*\n\n'
          'Olá, $cliente! Seu agendamento foi cancelado:\n\n'
          '📅 Data: $dateStr\n'
          '🕐 Hora: $timeStr\n'
          '✂️ Serviço: $servico\n\n'
          'Para reagendar acesse nosso app. 😊';
      WhatsappService.sendMessage(phone: phone, message: msg, config: config);
    });
  }

  Future<void> _rescheduleAppointment(Map<String, dynamic> appointment) async {
    if (!mounted) return;
    final rescheduled = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RescheduleModal(appointment: appointment),
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
            constraints: const BoxConstraints(maxWidth: 430),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: _HistoryPalette.bg),
              child: RefreshIndicator(
                color: _HistoryPalette.gold,
                backgroundColor: _HistoryPalette.panel,
                onRefresh: _refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _HistoryHeader(
                        customerName:
                            customerName == null || customerName.isEmpty
                            ? null
                            : customerName,
                        phone: _phone,
                        count: _appointments.length,
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
                          title: 'Consulte pelo telefone',
                          subtitle:
                              'Use o celular informado no agendamento para carregar os horarios.',
                          actionLabel: 'Informar telefone',
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
                              'Confira o telefone informado ou consulte outro numero.',
                          actionLabel: 'Trocar telefone',
                          onAction: _showPhoneDialog,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 96),
                        sliver: SliverList.builder(
                          itemCount: _appointments.length,
                          itemBuilder: (context, index) {
                            final appointment = _appointments[index];
                            final previous = index == 0
                                ? null
                                : _appointments[index - 1];
                            final showDay =
                                previous == null ||
                                _dayKey(previous) != _dayKey(appointment);
                            final expanded = _expandedIndex == index;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showDay)
                                  _DaySeparator(label: _dayLabel(appointment)),
                                _AppointmentCard(
                                  appointment: appointment,
                                  expanded: expanded,
                                  onTap: () {
                                    setState(() {
                                      _expandedIndex = expanded ? null : index;
                                    });
                                  },
                                  onCancel: () =>
                                      _cancelAndNotify(appointment),
                                  onReschedule: () =>
                                      _rescheduleAppointment(appointment),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HistoryPalette.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _HistoryPalette.stroke),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _DialogIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Buscar historico',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _HistoryPalette.text,
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
                  color: _HistoryPalette.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                inputFormatters: [widget.formatter],
                style: const TextStyle(color: _HistoryPalette.text),
                cursorColor: _HistoryPalette.gold,
                decoration: InputDecoration(
                  hintText: '(00) 00000-0000',
                  errorText: _error,
                  prefixIcon: const Icon(
                    Icons.phone_rounded,
                    color: _HistoryPalette.gold,
                  ),
                  filled: true,
                  fillColor: _HistoryPalette.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _HistoryPalette.stroke),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _HistoryPalette.stroke),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _HistoryPalette.gold),
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
                        foregroundColor: _HistoryPalette.muted,
                        side: const BorderSide(color: _HistoryPalette.stroke),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Agora nao'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final phone = _controller.text.trim();
                        if (_digits(phone).length < 10) {
                          setState(() => _error = 'Telefone incompleto');
                          return;
                        }
                        Navigator.of(context).pop(phone);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _HistoryPalette.gold,
                        foregroundColor: _HistoryPalette.bg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Consultar'),
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
}

class _DialogIcon extends StatelessWidget {
  const _DialogIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HistoryPalette.gold.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.manage_search_rounded,
          color: _HistoryPalette.gold,
        ),
      ),
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Historico',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _HistoryPalette.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Trocar telefone',
                onPressed: onChangePhone,
                icon: const Icon(
                  Icons.phone_forwarded_rounded,
                  color: _HistoryPalette.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            customerName == null
                ? 'Consulte os horarios pelo celular do cliente.'
                : 'Agendamentos de $customerName',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _HistoryPalette.muted),
          ),
          const SizedBox(height: 18),
          DecoratedBox(
            decoration: BoxDecoration(
              color: _HistoryPalette.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _HistoryPalette.stroke),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    color: _HistoryPalette.gold,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phone ?? 'Telefone nao informado',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: _HistoryPalette.text,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count agendamento${count == 1 ? '' : 's'} encontrado${count == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _HistoryPalette.muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onChangePhone,
                    style: TextButton.styleFrom(
                      foregroundColor: _HistoryPalette.gold,
                    ),
                    child: const Text('Alterar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: _HistoryPalette.gold,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.expanded,
    required this.onTap,
    required this.onCancel,
    required this.onReschedule,
  });

  final Map<String, dynamic> appointment;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context) {
    final status = _statusInfo(appointment['status']?.toString());
    final dateTime = _appointmentDateTime(appointment);

    final canCancel =
        status.raw != 'cancelled' &&
        status.raw != 'canceled' &&
        status.raw != 'completed' &&
        status.raw != 'attended' &&
        status.raw != 'no_show';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _HistoryPalette.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _HistoryPalette.stroke),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: status.color,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                ),
                child: const SizedBox(width: 5),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _StatusPill(status: status),
                          const Spacer(),
                          Text(
                            DateFormat('HH:mm', 'pt_BR').format(dateTime),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: _HistoryPalette.gold,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _serviceName(appointment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _HistoryPalette.text,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 7),
                      _DetailLine(
                        icon: Icons.person_rounded,
                        text: _barberName(appointment),
                      ),
                      _DetailLine(
                        icon: Icons.attach_money_rounded,
                        text: _priceLabel(appointment),
                      ),
                      if (expanded) ...[
                        const Divider(
                          color: _HistoryPalette.stroke,
                          height: 22,
                        ),
                        _DetailLine(
                          icon: Icons.calendar_month_rounded,
                          text: DateFormat(
                            "EEEE, dd/MM/yyyy 'as' HH:mm",
                            'pt_BR',
                          ).format(dateTime),
                        ),
                        _DetailLine(
                          icon: Icons.receipt_long_rounded,
                          text:
                              'Codigo ${appointment['id']?.toString().substring(0, 8) ?? '-'}',
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
                              backgroundColor: _HistoryPalette.gold,
                              foregroundColor: _HistoryPalette.bg,
                              minimumSize: const Size(double.infinity, 44),
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
                              foregroundColor: _HistoryPalette.danger,
                              backgroundColor:
                                  _HistoryPalette.danger.withValues(alpha: 0.10),
                              side: const BorderSide(
                                color: _HistoryPalette.danger,
                                width: 1.5,
                              ),
                              minimumSize: const Size(double.infinity, 44),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final _StatusInfo status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
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
          Icon(icon, color: _HistoryPalette.gold, size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _HistoryPalette.muted,
                fontWeight: FontWeight.w700,
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
                color: _HistoryPalette.text,
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
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: _HistoryPalette.gold,
                foregroundColor: _HistoryPalette.bg,
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

String _dayKey(Map<String, dynamic> appointment) {
  return DateFormat(
    'yyyy-MM-dd',
    'pt_BR',
  ).format(_appointmentDateTime(appointment));
}

String _dayLabel(Map<String, dynamic> appointment) {
  return DateFormat(
    'EEEE, dd/MM',
    'pt_BR',
  ).format(_appointmentDateTime(appointment));
}

String _serviceName(Map<String, dynamic> appointment) {
  final service = appointment['services'];
  if (service is Map && service['name'] != null) {
    return service['name'].toString();
  }
  return 'Servico';
}

String _barberName(Map<String, dynamic> appointment) {
  final barber = appointment['barbers'];
  if (barber is Map && barber['name'] != null) {
    return 'Profissional ${barber['name']}';
  }
  return 'Profissional nao informado';
}

String _priceLabel(Map<String, dynamic> appointment) {
  final raw =
      appointment['total_price'] ??
      ((appointment['services'] is Map)
          ? (appointment['services'] as Map)['price']
          : null);
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
  return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
}

_StatusInfo _statusInfo(String? rawStatus) {
  final raw = (rawStatus ?? 'scheduled').trim().toLowerCase();
  switch (raw) {
    case 'confirmed':
      return const _StatusInfo(
        'confirmed',
        'Confirmado',
        Icons.check_circle_rounded,
        _HistoryPalette.success,
      );
    case 'cancelled':
    case 'canceled':
      return const _StatusInfo(
        'cancelled',
        'Cancelado',
        Icons.cancel_rounded,
        _HistoryPalette.danger,
      );
    case 'completed':
    case 'attended':
      return const _StatusInfo(
        'completed',
        'Concluido',
        Icons.task_alt_rounded,
        _HistoryPalette.mint,
      );
    case 'no_show':
      return const _StatusInfo(
        'no_show',
        'Ausente',
        Icons.person_off_rounded,
        _HistoryPalette.muted,
      );
    case 'pending':
      return const _StatusInfo(
        'pending',
        'Pendente',
        Icons.schedule_rounded,
        _HistoryPalette.gold,
      );
    default:
      return const _StatusInfo(
        'scheduled',
        'Agendado',
        Icons.event_available_rounded,
        _HistoryPalette.gold,
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

// ── Modal de remarcação ───────────────────────────────────────────────────────

class _RescheduleModal extends StatefulWidget {
  const _RescheduleModal({required this.appointment});
  final Map<String, dynamic> appointment;

  @override
  State<_RescheduleModal> createState() => _RescheduleModalState();
}

class _RescheduleModalState extends State<_RescheduleModal> {
  DateTime?      _selectedDate;
  TimeOfDay?     _selectedTime;
  DateTime?      _selectedDateTime;
  List<TimeOfDay> _availableSlots = const [];
  Set<String>    _takenSlots     = const {};
  bool _loadingSlots = false;
  bool _saving       = false;

  Map<String, dynamic> get _ap => widget.appointment;
  String get _barberId      => _ap['barber_id']?.toString()      ?? '';
  String get _serviceId     => _ap['service_id']?.toString()     ?? '';
  String get _customerName  => _ap['customer_name']?.toString()  ?? '';
  String get _customerPhone => _ap['customer_phone']?.toString() ?? '';
  double get _totalPrice    => (_ap['total_price'] as num?)?.toDouble() ?? 0;
  String get _oldId         => _ap['id']?.toString()             ?? '';

  String get _barberName {
    final b = _ap['barbers'];
    return (b is Map ? b['name'] : null)?.toString() ?? '—';
  }

  String get _serviceName {
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
        enabled   = (row['is_available'] ?? true) == true;
        final st  = '${row['start_time'] ?? '09:00'}'.split(':');
        final et  = '${row['end_time']   ?? '18:00'}'.split(':');
        start = TimeOfDay(hour: int.tryParse(st[0]) ?? 9,  minute: int.tryParse(st[1]) ?? 0);
        end   = TimeOfDay(hour: int.tryParse(et[0]) ?? 18, minute: int.tryParse(et[1]) ?? 0);
      }

      final slots = <TimeOfDay>[];
      if (enabled) {
        var cur    = DateTime(date.year, date.month, date.day, start.hour, start.minute);
        final endDt = DateTime(date.year, date.month, date.day, end.hour,   end.minute);
        while (cur.isBefore(endDt) || cur.isAtSameMomentAs(endDt)) {
          slots.add(TimeOfDay(hour: cur.hour, minute: cur.minute));
          cur = cur.add(const Duration(minutes: 30));
        }
      }

      final dateStr  = DateFormat('yyyy-MM-dd').format(date);
      final takenRows = await Supabase.instance.client
          .from('appointments')
          .select('id, appointment_time, status')
          .eq('barber_id', _barberId)
          .eq('appointment_date', dateStr);

      final taken = <String>{};
      for (final r in takenRows as List) {
        final m = r as Map<String, dynamic>;
        // Libera o horário do agendamento sendo remarcado
        if (m['id']?.toString() == _oldId) continue;
        final st = m['status']?.toString() ?? '';
        if (st == 'cancelled' || st == 'canceled' || st == 'no_show') continue;
        final parts = (m['appointment_time']?.toString() ?? '').split(':');
        if (parts.length >= 2) {
          taken.add('${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}');
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

      // Cria novo agendamento
      await Supabase.instance.client.from('appointments').insert({
        'service_id':      _serviceId,
        'barber_id':       _barberId,
        'appointment_date': dateStr,
        'appointment_time': timeStr,
        'status':          'scheduled',
        'customer_name':   _customerName,
        'customer_phone':  _customerPhone,
        'notes':           'Reagendamento — $_customerName / $_customerPhone',
        'total_price':     _totalPrice,
      });

      // Cancela o agendamento antigo → libera o horário
      await Supabase.instance.client
          .from('appointments')
          .update({'status': 'cancelled'})
          .eq('id', _oldId);

      // WhatsApp
      final dateF   = DateFormat('dd/MM/yyyy', 'pt_BR').format(dt);
      final timeF   = DateFormat('HH:mm').format(dt);
      final nome    = _customerName;
      final fone    = _customerPhone;
      final servico = _serviceName;
      final barbeiro = _barberName;
      WhatsappService.loadConfig().then((config) {
        if (!config.enabled || !config.isConfigured) return;
        final msg = '🔄 *Agendamento remarcado!*\n\n'
            'Olá, $nome! Seu novo horário está confirmado:\n\n'
            '📅 Data: $dateF\n'
            '🕐 Hora: $timeF\n'
            '✂️ Serviço: $servico\n'
            '💈 Profissional: $barbeiro\n\n'
            'Te esperamos! 😊';
        WhatsappService.sendMessage(phone: fone, message: msg, config: config);
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
        color: _HistoryPalette.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: _HistoryPalette.stroke)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: _HistoryPalette.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Remarcar agendamento',
              style: TextStyle(
                color: _HistoryPalette.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$_serviceName  •  $_barberName',
              style: const TextStyle(color: _HistoryPalette.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Seleção de data
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
                        primary:   _HistoryPalette.gold,
                        onPrimary: _HistoryPalette.bg,
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
                size: 16,
                color: _HistoryPalette.gold,
              ),
              label: Text(
                _selectedDate == null
                    ? 'Selecionar nova data'
                    : DateFormat('EEEE, dd/MM/yyyy', 'pt_BR').format(_selectedDate!),
                style: const TextStyle(color: _HistoryPalette.gold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _HistoryPalette.gold),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Horários disponíveis
            if (_loadingSlots)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(color: _HistoryPalette.gold),
                ),
              )
            else if (_selectedDate != null && _availableSlots.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nenhum horário disponível neste dia.',
                  style: TextStyle(color: _HistoryPalette.muted),
                ),
              )
            else if (_availableSlots.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableSlots.map((t) {
                  final label   = '${t.hour.toString().padLeft(2, '0')}:'
                      '${t.minute.toString().padLeft(2, '0')}';
                  final taken   = _takenSlots.contains(label);
                  final selected = _selectedTime == t;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    selectedColor: _HistoryPalette.gold,
                    backgroundColor: _HistoryPalette.card,
                    disabledColor: _HistoryPalette.card.withValues(alpha: 0.4),
                    side: BorderSide(
                      color: selected
                          ? _HistoryPalette.gold
                          : _HistoryPalette.stroke,
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? _HistoryPalette.bg
                          : taken
                              ? _HistoryPalette.muted
                              : _HistoryPalette.text,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                    onSelected: taken
                        ? null
                        : (v) {
                            if (!v) return;
                            setState(() {
                              _selectedTime     = t;
                              _selectedDateTime = DateTime(
                                _selectedDate!.year,
                                _selectedDate!.month,
                                _selectedDate!.day,
                                t.hour,
                                t.minute,
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
                        strokeWidth: 2,
                        color: _HistoryPalette.bg,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_saving ? 'Remarcando...' : 'Confirmar remarcação'),
              style: FilledButton.styleFrom(
                backgroundColor: _selectedDateTime != null
                    ? _HistoryPalette.gold
                    : _HistoryPalette.stroke,
                foregroundColor: _HistoryPalette.bg,
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

class _HistoryPalette {
  static const Color frame = Color(0xFF223C3C);
  static const Color bg = Color(0xFF0F0C0B);
  static const Color panel = Color(0xFF1C1714);
  static const Color card = Color(0xFF181110);
  static const Color stroke = Color(0xFF37241F);
  static const Color text = Color(0xFFFFF6EA);
  static const Color muted = Color(0xFFB9A394);
  static const Color gold = Color(0xFFF6C84F);
  static const Color mint = Color(0xFF20D8B2);
  static const Color danger = Color(0xFFE85B4D);
  static const Color success = Color(0xFF4CAF50);
}
