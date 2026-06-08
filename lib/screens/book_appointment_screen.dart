import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/models/service.dart';
import 'package:barbearia/services/whatsapp_service.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class BarberLite {
  final String id;
  final String name;
  final String avatarUrl;
  final double rating;
  final String phone;
  final bool isAvailable;

  BarberLite({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.rating,
    this.phone = '',
    this.isAvailable = true,
  });

  factory BarberLite.fromMap(Map<String, dynamic> map) {
    final rawRating = map['rating'] ?? map['score'] ?? map['stars'];
    final doubleRating = rawRating is num
        ? rawRating.toDouble()
        : double.tryParse('${rawRating ?? ''}') ?? 0.0;

    final avatar =
        (map['avatar_url'] ??
                map['avatar'] ??
                map['photo_url'] ??
                map['image_url'] ??
                '')
            .toString();

    return BarberLite(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      avatarUrl: avatar,
      rating: doubleRating,
      phone: (map['phone'] ?? map['telefone'] ?? '').toString(),
      isAvailable: (map['is_available'] ?? true) == true,
    );
  }
}

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key, this.service});

  final Service? service;

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  // Fluxo: Serviço (0) → Data (1) → Barbeiro (2) → Horário (3) → Dados (4)
  int _currentStep = 0;

  // Passo 0 – Serviços
  List<Service> _selectedServices = const [];

  // Passo 1 – Data
  DateTime? _selectedDate;
  int _datePageOffset = 0;

  // Passo 2 – Barbeiro
  String? _selectedBarberId;
  bool _loadingBarbers = true;
  String? _barbersError;
  List<BarberLite> _barbers = const [];
  // barber_id → disponível no dia selecionado (null = não encontrado = disponível)
  Map<String, bool> _barberDayAvailable = {};
  bool _loadingAvailability = false;

  // Passo 3 – Horário
  List<TimeOfDay> _availableSlots = const [];
  Set<String> _takenSlots = const {};
  TimeOfDay? _selectedTime;
  DateTime? _selectedDateTime;

  // Passo 4 – Dados pessoais
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phoneMask = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {'#': RegExp(r'[0-9]')},
  );
  bool _isPlanClient = false;
  bool _checkingPlan = false;

  @override
  void initState() {
    super.initState();
    if (widget.service != null) {
      _selectedServices = [widget.service!];
    }
    _loadBarbers();
    initializeDateFormatting('pt_BR');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadBarbers() async {
    setState(() {
      _loadingBarbers = true;
      _barbersError = null;
    });

    try {
      final data = await Supabase.instance.client
          .from('barbers')
          .select('*')
          .order('name');

      final list = (data as List).cast<Map<String, dynamic>>();
      final parsed = list.map(BarberLite.fromMap).toList();

      if (!mounted) return;
      setState(() {
        _barbers = parsed;
        _loadingBarbers = false;
      });
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('oauth_client_id')) {
        try {
          await Supabase.instance.client.auth.signOut();
          final data = await Supabase.instance.client
              .from('barbers')
              .select('*')
              .order('name');
          final list = (data as List).cast<Map<String, dynamic>>();
          final parsed = list.map(BarberLite.fromMap).toList();
          if (!mounted) return;
          setState(() {
            _barbers = parsed;
            _loadingBarbers = false;
          });
          return;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _barbersError = 'Erro: $e';
        _loadingBarbers = false;
      });
    }
  }

  /// Carrega quais barbeiros estão disponíveis na data selecionada.
  /// Verifica escala semanal (barber_availability) e bloqueios específicos (barber_blocked_days).
  Future<void> _loadBarberAvailability() async {
    if (_selectedDate == null || _barbers.isEmpty) return;
    setState(() => _loadingAvailability = true);

    final dow = _selectedDate!.weekday; // 1=Seg … 7=Dom
    final dayOfWeek = dow == 7 ? 0 : dow;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);

    try {
      // 1. Escala semanal recorrente
      final avRows = await Supabase.instance.client
          .from('barber_availability')
          .select('barber_id, is_available')
          .eq('day_of_week', dayOfWeek);

      final avail = <String, bool>{};
      for (final row in avRows) {
        avail[row['barber_id'].toString()] =
            (row['is_available'] ?? true) == true;
      }

      // 2. Bloqueios de dia/período específicos
      try {
        final blocked = await Supabase.instance.client
            .from('barber_blocked_days')
            .select('barber_id')
            .lte('date_from', dateStr)
            .gte('date_to', dateStr);

        for (final row in blocked) {
          avail[row['barber_id'].toString()] = false;
        }
      } catch (_) {} // ignora se tabela ainda não existir

      // 3. Barbeiro desativado globalmente (is_available = false)
      for (final b in _barbers) {
        if (!b.isAvailable) avail[b.id] = false;
      }

      if (!mounted) return;
      setState(() {
        _barberDayAvailable = avail;
        _loadingAvailability = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _barberDayAvailable = {};
        _loadingAvailability = false;
      });
    }
  }

  Future<void> _checkPlanClient(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.length < 10) {
      if (_isPlanClient) setState(() => _isPlanClient = false);
      return;
    }
    setState(() => _checkingPlan = true);
    try {
      final rows = await Supabase.instance.client
          .from('plan_clients')
          .select('id')
          .eq('phone', normalized)
          .limit(1);
      if (!mounted) return;
      setState(() {
        _isPlanClient = rows.isNotEmpty;
        _checkingPlan = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPlanClient = false;
        _checkingPlan = false;
      });
    }
  }

  Future<void> _refreshSlots() async {
    final barberId = _selectedBarberId;
    final selDate = _selectedDate;
    if (barberId == null || selDate == null) {
      setState(() {
        _availableSlots = const [];
        _takenSlots = const {};
        _selectedTime = null;
        _selectedDateTime = null;
      });
      return;
    }
    try {
      final dow = selDate.weekday;
      final avRows = await Supabase.instance.client
          .from('barber_availability')
          .select('*')
          .eq('barber_id', barberId)
          .eq('day_of_week', dow == 7 ? 0 : dow)
          .limit(1);
      TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
      TimeOfDay end = const TimeOfDay(hour: 18, minute: 0);
      bool enabled = true;
      if (avRows.isNotEmpty) {
        final row = avRows.first;
        enabled = (row['is_available'] ?? true) == true;
        final st = '${row['start_time'] ?? '09:00:00'}'.split(':');
        final et = '${row['end_time'] ?? '18:00:00'}'.split(':');
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
        var cur = DateTime(
          selDate.year,
          selDate.month,
          selDate.day,
          start.hour,
          start.minute,
        );
        final endDt = DateTime(
          selDate.year,
          selDate.month,
          selDate.day,
          end.hour,
          end.minute,
        );
        while (cur.isBefore(endDt) || cur.isAtSameMomentAs(endDt)) {
          slots.add(TimeOfDay(hour: cur.hour, minute: cur.minute));
          cur = cur.add(const Duration(minutes: 30));
        }
      }
      final appointmentDate = _dateOnlyForDb(selDate);
      dynamic takenRows;
      try {
        takenRows = await Supabase.instance.client
            .from('appointments')
            .select('appointment_time,status')
            .eq('barber_id', barberId)
            .eq('appointment_date', appointmentDate)
            .or(
              'status.eq.scheduled,status.eq.confirmed,status.eq.in_progress',
            );
      } catch (_) {
        takenRows = await Supabase.instance.client
            .from('appointments')
            .select('appointment_time')
            .eq('barber_id', barberId)
            .eq('appointment_date', appointmentDate);
      }
      final taken = <String>{};
      if (takenRows is List) {
        for (final r in takenRows) {
          final map = r as Map<String, dynamic>;
          final st = (map['status'] ?? '').toString();
          if (st.isNotEmpty && (st == 'cancelled' || st == 'no_show')) {
            continue;
          }
          final time = _timeForDb(map['appointment_time']);
          if (time != null) taken.add(time);
        }
      }

      // Horários bloqueados pelo admin também ficam indisponíveis
      try {
        final blockedRows = await Supabase.instance.client
            .from('blocked_slots')
            .select('time')
            .eq('barber_id', barberId)
            .eq('date', appointmentDate);
        for (final r in blockedRows) {
          final t = _timeForDb(r['time']);
          if (t != null) taken.add(t);
        }
      } catch (_) {}

      setState(() {
        _availableSlots = slots;
        _takenSlots = taken;
        _selectedTime = null;
        _selectedDateTime = null;
      });
    } catch (e) {
      setState(() {
        _availableSlots = const [];
        _takenSlots = const {};
        _selectedTime = null;
        _selectedDateTime = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar horários: $e')),
        );
      }
    }
  }

  bool _slotFits(int startIndex) {
    final n = _selectedServices.isEmpty ? 1 : _selectedServices.length;
    if (startIndex + n > _availableSlots.length) return false;
    for (var k = 0; k < n; k++) {
      final t = _availableSlots[startIndex + k];
      final label =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      if (_takenSlots.contains(label)) return false;
    }
    return true;
  }

  bool _hasSelectableSlot() {
    for (var i = 0; i < _availableSlots.length; i++) {
      final t = _availableSlots[i];
      final label =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      if (!_takenSlots.contains(label) && _slotFits(i)) return true;
    }
    return false;
  }

  Future<void> _saveAppointment() async {
    final barberId = _selectedBarberId;
    final dt = _selectedDateTime;
    if (_selectedServices.isEmpty ||
        barberId == null ||
        dt == null ||
        _nameController.text.isEmpty ||
        _phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos antes de salvar.'),
        ),
      );
      return;
    }

    try {
      final n = _selectedServices.length;
      final appointmentDate = _dateOnlyForDb(dt);
      final slotTimes =
          List.generate(n, (i) => dt.add(Duration(minutes: 30 * i)));
      final wantedHHmm = slotTimes
          .map((d) =>
              '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}')
          .toList();

      final existing = await Supabase.instance.client
          .from('appointments')
          .select('appointment_time,status')
          .eq('barber_id', barberId)
          .eq('appointment_date', appointmentDate);
      final occupied = <String>{};
      for (final m in existing) {
        final st = (m['status'] ?? '').toString();
        if (st == 'cancelled' || st == 'no_show') continue;
        final t = _timeForDb(m['appointment_time']);
        if (t != null) occupied.add(t);
      }
      final hasConflict = wantedHHmm.any(occupied.contains);
      if (hasConflict) {
        await showDialog(
          context: context,
          builder: (ctx) {
            final theme = Theme.of(ctx);
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  const Text('Horário indisponível'),
                ],
              ),
              content: Text(
                n > 1
                    ? 'Um dos horários necessários para esses $n serviços já está ocupado. Escolha outro horário.'
                    : 'Este barbeiro já possui agendamento neste horário.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return;
      }
      final authUser = Supabase.instance.client.auth.currentUser;
      final isAdmin = authUser != null && !authUser.isAnonymous;

      final payload = <Map<String, dynamic>>[];
      for (var i = 0; i < n; i++) {
        final s = _selectedServices[i];
        final slotDt = slotTimes[i];
        payload.add({
          'service_id': s.id,
          'barber_id': barberId,
          'appointment_date': _dateOnlyForDb(slotDt),
          'appointment_time': _timeOnlyForDb(slotDt),
          'status': 'scheduled',
          'customer_name': _nameController.text.trim(),
          'customer_phone': _phoneController.text.trim(),
          'notes':
              'Cliente: ${_nameController.text.trim()}\nTelefone: ${_phoneController.text.trim()}',
          'total_price': s.price,
          'is_plan_client': _isPlanClient,
          'source': isAdmin ? 'admin' : 'client',
        });
      }

      final insertQuery = Supabase.instance.client
          .from('appointments')
          .insert(payload);
      dynamic response;
      response = await insertQuery.select();
      await showDialog(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final barber = _barbers.firstWhere(
            (b) => b.id == _selectedBarberId,
            orElse: () => BarberLite(
              id: '',
              name: 'Sem barbeiro',
              avatarUrl: '',
              rating: 0.0,
            ),
          );
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(child: Text('Agendamento confirmado')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Barbeiro: ${barber.name}'),
                const SizedBox(height: 6),
                Text('Data/Hora: ${_formatDateTime(_selectedDateTime!)}'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedServices
                      .map((s) => Chip(label: Text(s.name)))
                      .toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      _sendWhatsappConfirmation();

      if (mounted) Navigator.pop(context, response);
    } on PostgrestException catch (e) {
      await showDialog(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                const Text('Falha ao agendar'),
              ],
            ),
            content: Text('Erro: ${_bookingErrorMessage(e)}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      await showDialog(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                const Text('Erro inesperado'),
              ],
            ),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  String _dateOnlyForDb(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value);
  }

  String _timeOnlyForDb(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:00';
  }

  String? _timeForDb(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  String _bookingErrorMessage(PostgrestException e) {
    if (e.code == '42703' ||
        e.message.contains('customer_name') ||
        e.message.contains('customer_phone') ||
        e.message.contains('user_id')) {
      return 'O banco ainda não está preparado para agendamento público. Execute lib/supabase/public_booking_migration.sql no SQL Editor do Supabase.';
    }
    if (e.message.toLowerCase().contains('row-level security')) {
      return 'A policy de agendamento público ainda não foi aplicada no Supabase.';
    }
    return e.message;
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _BP.muted),
      prefixIcon: Icon(icon, color: _BP.muted, size: 20),
      filled: true,
      fillColor: _BP.card,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _BP.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _BP.gold, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _BP.bg,
      appBar: AppBar(
        backgroundColor: _BP.card,
        foregroundColor: _BP.text,
        elevation: 0,
        title: const Text(
          'Agendar Horário',
          style: TextStyle(color: _BP.text, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: _BP.gold),
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: _BP.gold,
            onPrimary: _BP.bg,
            surface: _BP.card,
            onSurface: _BP.text,
            outline: _BP.border,
          ),
          checkboxTheme: CheckboxThemeData(
            fillColor: WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.selected)
                    ? _BP.gold
                    : Colors.transparent),
            checkColor: WidgetStateProperty.all(_BP.bg),
            side: const BorderSide(color: _BP.border, width: 1.5),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        child: Stepper(
          currentStep: _currentStep,
          onStepCancel: () {
            if (_currentStep == 0) {
              Navigator.pop(context);
              return;
            }
            // Limpa estado ao voltar para não deixar seleção órfã
            if (_currentStep == 2) {
              setState(() {
                _selectedBarberId = null;
                _barberDayAvailable = {};
              });
            } else if (_currentStep == 3) {
              setState(() {
                _selectedTime = null;
                _selectedDateTime = null;
                _availableSlots = const [];
                _takenSlots = const {};
              });
            }
            setState(() => _currentStep--);
          },
          onStepContinue: () {
            if (_currentStep == 0) {
              if (_selectedServices.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Selecione ao menos um serviço.')),
                );
                return;
              }
              setState(() => _currentStep = 1);
              return;
            }
            if (_currentStep == 1) {
              if (_selectedDate == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Selecione uma data.')),
                );
                return;
              }
              // Carrega disponibilidade dos barbeiros ao entrar no passo 2
              _loadBarberAvailability();
              setState(() => _currentStep = 2);
              return;
            }
            if (_currentStep == 2) {
              if (_selectedBarberId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Selecione um barbeiro disponível.')),
                );
                return;
              }
              // Carrega horários ao entrar no passo 3
              _refreshSlots();
              setState(() => _currentStep = 3);
              return;
            }
            if (_currentStep == 3) {
              if (_selectedTime == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Selecione um horário.')),
                );
                return;
              }
              setState(() => _currentStep = 4);
              return;
            }
            _saveAppointment();
          },
          controlsBuilder: (context, details) {
            final isLast = _currentStep == 4;
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: details.onStepContinue,
                    style: FilledButton.styleFrom(
                      backgroundColor: _BP.gold,
                      foregroundColor: _BP.bg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      isLast ? 'Confirmar' : 'Continuar',
                      style:
                          const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    style:
                        TextButton.styleFrom(foregroundColor: _BP.muted),
                    child: const Text('Voltar'),
                  ),
                ],
              ),
            );
          },
          steps: [
            // ── Passo 0: Serviços ─────────────────────────────────────────
            Step(
              isActive: _currentStep >= 0,
              title: const Text('Escolha o Serviço'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MultiSelectServicesFromSupabase(
                    initialSelectedIds:
                        _selectedServices.map((s) => s.id).toSet(),
                    onChange: (list) =>
                        setState(() => _selectedServices = list),
                  ),
                ],
              ),
            ),

            // ── Passo 1: Data ─────────────────────────────────────────────
            Step(
              isActive: _currentStep >= 1,
              title: const Text('Escolha a Data'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selecione o dia desejado:',
                    style: TextStyle(color: _BP.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _datePageOffset == 0
                            ? null
                            : () =>
                                setState(() => _datePageOffset--),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          color: _datePageOffset == 0
                              ? _BP.border
                              : _BP.gold,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: List.generate(7, (i) {
                            final day = DateTime.now().add(
                              Duration(
                                  days: _datePageOffset * 7 + i),
                            );
                            final d = DateTime(
                                day.year, day.month, day.day);
                            final selected = _selectedDate == d;
                            final raw =
                                DateFormat('E', 'pt_BR')
                                    .format(d)
                                    .replaceFirst(
                                        RegExp(r'\.$'), '');
                            final dayName = raw.isEmpty
                                ? ''
                                : raw[0].toUpperCase() +
                                    raw.substring(1);
                            return GestureDetector(
                              onTap: () => setState(() {
                                _selectedDate = d;
                                // Limpa seleções posteriores ao mudar a data
                                _selectedBarberId = null;
                                _barberDayAvailable = {};
                                _selectedTime = null;
                                _selectedDateTime = null;
                                _availableSlots = const [];
                                _takenSlots = const {};
                              }),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 150),
                                width: 64,
                                padding:
                                    const EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? _BP.gold
                                          .withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  border: Border.all(
                                    color: selected
                                        ? _BP.gold
                                        : _BP.border,
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? _BP.gold
                                            : _BP.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      dayName,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: selected
                                            ? _BP.gold
                                            : _BP.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: _datePageOffset >= 7
                            ? null
                            : () =>
                                setState(() => _datePageOffset++),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: _datePageOffset >= 7
                              ? _BP.border
                              : _BP.gold,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                  if (_selectedDate != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: _BP.gold, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat("EEEE, dd/MM/yyyy", 'pt_BR')
                              .format(_selectedDate!),
                          style: const TextStyle(
                            color: _BP.gold,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ── Passo 2: Barbeiro ─────────────────────────────────────────
            Step(
              isActive: _currentStep >= 2,
              title: const Text('Escolha o Barbeiro'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadingBarbers)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_barbersError != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_barbersError!,
                              style:
                                  const TextStyle(color: _BP.muted)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _loadBarbers,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar novamente'),
                          ),
                        ],
                      ),
                    )
                  else if (_barbers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Nenhum barbeiro encontrado.',
                          style: TextStyle(color: _BP.muted)),
                    )
                  else ...[
                    if (_loadingAvailability)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _BP.gold),
                            ),
                            SizedBox(width: 8),
                            Text('Verificando disponibilidade...',
                                style: TextStyle(
                                    color: _BP.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                    ..._barbers.map(
                      (b) {
                        // null = não cadastrado em barber_availability → disponível
                        final availInDb = _barberDayAvailable[b.id];
                        final unavailable = availInDb == false;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _barberTile(
                            id: b.id,
                            name: b.name,
                            avatarUrl: b.avatarUrl,
                            rating: b.rating,
                            unavailable: unavailable,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),

            // ── Passo 3: Horário ──────────────────────────────────────────
            Step(
              isActive: _currentStep >= 3,
              title: const Text('Escolha o Horário'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedDate != null)
                    Text(
                      DateFormat("EEEE, dd/MM", 'pt_BR')
                          .format(_selectedDate!),
                      style: const TextStyle(
                        color: _BP.gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_selectedServices.length > 1) ...[
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 13, color: _BP.gold),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_selectedServices.length} serviços ocupam ${_selectedServices.length} horários seguidos (${_selectedServices.length * 30}min).',
                            style: const TextStyle(
                                color: _BP.muted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_availableSlots.isEmpty || !_hasSelectableSlot())
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _BP.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _BP.gold.withValues(alpha: 0.4)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.event_busy,
                              color: _BP.gold, size: 28),
                          SizedBox(height: 8),
                          Text(
                            'Sem horários disponíveis nesta data!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _BP.gold,
                                fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Volte e escolha outro barbeiro ou data.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _BP.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableSlots
                          .asMap()
                          .entries
                          .map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        final label =
                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                        final taken = _takenSlots.contains(label);
                        final disabled = taken || !_slotFits(i);
                        final selected = _selectedTime == t;
                        return ChoiceChip(
                          label: Text(label),
                          selected: selected,
                          selectedColor: _BP.gold,
                          backgroundColor: _BP.card,
                          disabledColor:
                              _BP.card.withValues(alpha: 0.4),
                          side: BorderSide(
                            color: selected ? _BP.gold : _BP.border,
                          ),
                          labelStyle: TextStyle(
                            color: selected
                                ? _BP.bg
                                : disabled
                                    ? _BP.muted
                                    : _BP.text,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                          onSelected: disabled
                              ? null
                              : (v) {
                                  if (!v) return;
                                  setState(() {
                                    _selectedTime = t;
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
                ],
              ),
            ),

            // ── Passo 4: Dados pessoais ───────────────────────────────────
            Step(
              isActive: _currentStep >= 4,
              title: const Text('Dados Pessoais'),
              content: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: _BP.text),
                    decoration:
                        _inputDeco('Nome completo', Icons.person_outline),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: _BP.text),
                    inputFormatters: [_phoneMask],
                    onChanged: _checkPlanClient,
                    decoration:
                        _inputDeco('Telefone', Icons.phone_outlined)
                            .copyWith(hintText: '(00) 00000-0000'),
                  ),
                  if (_checkingPlan)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Verificando plano...',
                              style: TextStyle(
                                  color: _BP.muted, fontSize: 12)),
                        ],
                      ),
                    )
                  else if (_isPlanClient)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.green.shade400),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.card_membership,
                              color: Colors.green.shade400, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Cliente Mensalista',
                            style: TextStyle(
                              color: Colors.green.shade400,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendWhatsappConfirmation() {
    final dt = _selectedDateTime;
    final phone = _phoneController.text.trim();
    final cliente = _nameController.text.trim();
    if (dt == null || phone.isEmpty || _selectedServices.isEmpty) return;

    final barber = _barbers.firstWhere(
      (b) => b.id == _selectedBarberId,
      orElse: () =>
          BarberLite(id: '', name: '—', avatarUrl: '', rating: 0),
    );

    final dateStr = DateFormat('dd/MM/yyyy', 'pt_BR').format(dt);
    final timeStr = DateFormat('HH:mm').format(dt);
    final services = _selectedServices.map((s) => s.name).join(', ');
    final totalPrice = _selectedServices.fold<double>(
        0, (sum, s) => sum + s.price);
    final valor =
        'R\$ ${totalPrice.toStringAsFixed(2).replaceAll('.', ',')}';

    WhatsappService.loadConfig().then((config) {
      if (!config.enabled || !config.isConfigured) return;
      final msg = WhatsappService.buildMessage(
        template: config.template,
        cliente: cliente,
        data: dateStr,
        hora: timeStr,
        servico: services,
        barbeiro: barber.name,
        valor: valor,
      );
      WhatsappService.sendMessage(
          phone: phone, message: msg, config: config);

      final barberPhone = barber.phone.trim();
      if (barberPhone.isNotEmpty) {
        final msgBarbeiro = '📅 *Novo agendamento!*\n\n'
            '👤 Cliente: $cliente\n'
            '📞 Telefone: $phone\n'
            '✂️ Serviço: $services\n'
            '🗓️ Data: $dateStr às $timeStr\n'
            '💰 Valor: $valor';
        WhatsappService.sendMessage(
          phone: barberPhone,
          message: msgBarbeiro,
          config: config,
        );
      }
    });
  }

  Widget _barberTile({
    required String id,
    required String name,
    required String avatarUrl,
    required double rating,
    bool unavailable = false,
  }) {
    final selected = _selectedBarberId == id;

    return Opacity(
      opacity: unavailable ? 0.45 : 1.0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: unavailable
            ? null
            : () async {
                setState(() => _selectedBarberId = id);
              },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? _BP.gold.withValues(alpha: 0.08)
                : _BP.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _BP.gold : _BP.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _BP.border,
                foregroundImage: avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl.isEmpty
                    ? const Icon(Icons.person, color: _BP.muted)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: unavailable ? _BP.muted : _BP.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (unavailable) ...[
                      const SizedBox(height: 2),
                      const Text(
                        'Indisponível nesta data',
                        style: TextStyle(
                          color: Color(0xFFF06666),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected && !unavailable)
                const Icon(Icons.check_circle_rounded,
                    color: _BP.gold, size: 20),
              if (unavailable)
                const Icon(Icons.block,
                    color: Color(0xFFF06666), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _MultiSelectServicesFromSupabase extends StatefulWidget {
  const _MultiSelectServicesFromSupabase({
    required this.onChange,
    this.initialSelectedIds = const {},
  });
  final void Function(List<Service>) onChange;
  final Set<String> initialSelectedIds;

  @override
  State<_MultiSelectServicesFromSupabase> createState() =>
      _MultiSelectServicesFromSupabaseState();
}

class _MultiSelectServicesFromSupabaseState
    extends State<_MultiSelectServicesFromSupabase> {
  late final Future<List<Service>> _servicesFuture;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _servicesFuture = _fetchServices();
    if (widget.initialSelectedIds.isNotEmpty) {
      _selectedIds.addAll(widget.initialSelectedIds);
    }
  }

  Future<List<Service>> _fetchServices() async {
    final response = await Supabase.instance.client
        .from('services')
        .select()
        .order('name');
    return (response as List)
        .map((serviceData) => Service.fromMap(serviceData))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Service>>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        final services = snapshot.data ?? [];
        if (services.isEmpty) {
          return const Center(child: Text('Nenhum serviço encontrado.'));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecione um ou mais serviços:',
              style: TextStyle(color: _BP.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            ...services.map((s) {
              final checked = _selectedIds.contains(s.id);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (checked) {
                      _selectedIds.remove(s.id);
                    } else {
                      _selectedIds.add(s.id);
                    }
                  });
                  final selected = services
                      .where((it) => _selectedIds.contains(it.id))
                      .toList();
                  widget.onChange(selected);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: checked
                        ? _BP.gold.withValues(alpha: 0.08)
                        : _BP.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: checked ? _BP.gold : _BP.border,
                      width: checked ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedIds.add(s.id);
                            } else {
                              _selectedIds.remove(s.id);
                            }
                          });
                          final selected = services
                              .where((it) => _selectedIds.contains(it.id))
                              .toList();
                          widget.onChange(selected);
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: TextStyle(
                                color: checked ? _BP.gold : _BP.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.formattedPrice,
                              style: const TextStyle(
                                color: _BP.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ── Paleta dark ───────────────────────────────────────────────────────────────

class _BP {
  static const Color bg = Color(0xFF0C0D10);
  static const Color card = Color(0xFF14161A);
  static const Color border = Color(0xFF252830);
  static const Color gold = Color(0xFFF5C440);
  static const Color text = Color(0xFFF0EDE8);
  static const Color muted = Color(0xFF6B7280);
}

String _formatDateTime(DateTime dt) {
  final f = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  return f.format(dt);
}
