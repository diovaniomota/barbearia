import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/models/service.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class BarberLite {
  final String id;
  final String name;
  final String avatarUrl;
  final double rating;

  BarberLite({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.rating,
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
  int _currentStep = 0;

  List<Service> _selectedServices = const [];
  String? _selectedBarberId;
  DateTime? _selectedDateTime;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  List<TimeOfDay> _availableSlots = const [];
  Set<String> _takenSlots = const {};

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _loadingBarbers = true;
  String? _barbersError;
  List<BarberLite> _barbers = const [];

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
      final dow = selDate.weekday; // 1..7 (Seg..Dom)
      final avRows = await Supabase.instance.client
          .from('barber_availability')
          .select('*')
          .eq('barber_id', barberId)
          .eq('day_of_week', dow == 7 ? 0 : dow)
          .limit(1);
      TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
      TimeOfDay end = const TimeOfDay(hour: 18, minute: 0);
      bool enabled = true;
      if (avRows is List && avRows.isNotEmpty) {
        final row = avRows.first as Map<String, dynamic>;
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
      dynamic conflict;
      final appointmentDate = _dateOnlyForDb(dt);
      final appointmentTime = _timeOnlyForDb(dt);
      try {
        conflict = await Supabase.instance.client
            .from('appointments')
            .select('id,status')
            .eq('barber_id', barberId)
            .eq('appointment_date', appointmentDate)
            .eq('appointment_time', appointmentTime)
            .or('status.eq.scheduled,status.eq.confirmed,status.eq.in_progress')
            .limit(1);
      } catch (_) {
        conflict = await Supabase.instance.client
            .from('appointments')
            .select('id')
            .eq('barber_id', barberId)
            .eq('appointment_date', appointmentDate)
            .eq('appointment_time', appointmentTime)
            .limit(1);
      }
      if (conflict is List && conflict.isNotEmpty) {
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
              content: const Text(
                'Este barbeiro já possui agendamento neste horário.',
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
      final payload = _selectedServices.map((s) {
        return {
          'service_id': s.id,
          'barber_id': barberId,
          'appointment_date': appointmentDate,
          'appointment_time': appointmentTime,
          'status': 'scheduled',
          'customer_name': _nameController.text.trim(),
          'customer_phone': _phoneController.text.trim(),
          'notes':
              'Cliente: ${_nameController.text.trim()}\nTelefone: ${_phoneController.text.trim()}',
          'total_price': s.price,
        };
      }).toList();

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

      Navigator.pop(context, response);
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

  Future<void> _showConfirmationDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Agendamento confirmado!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedServices.isNotEmpty)
                Text(
                  'Serviços: ${_selectedServices.map((s) => s.name).join(', ')}',
                ),
              if (_selectedDateTime != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Quando: ${_selectedDateTime!.toLocal()}'),
                ),
              if (_selectedBarberId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Barbeiro: ${_barbers.firstWhere(
                      (b) => b.id == _selectedBarberId,
                      orElse: () => BarberLite(id: _selectedBarberId!, name: 'Selecionado', avatarUrl: '', rating: 0),
                    ).name}',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
                s.contains(WidgetState.selected) ? _BP.gold : Colors.transparent),
            checkColor: WidgetStateProperty.all(_BP.bg),
            side: const BorderSide(color: _BP.border, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        child: Stepper(
          currentStep: _currentStep,
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
          onStepContinue: () {
            if (_currentStep == 0) {
              if (_selectedServices.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione ao menos um serviço.'),
                  ),
                );
                return;
              }
              setState(() => _currentStep = 1);
              return;
            }
            if (_currentStep < 3) {
              setState(() => _currentStep++);
            } else {
              _saveAppointment();
            }
          },
          controlsBuilder: (context, details) {
            final isLast = _currentStep == 3;
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
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    style: TextButton.styleFrom(foregroundColor: _BP.muted),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            );
          },
          steps: [
            Step(
              isActive: _currentStep >= 0,
              title: const Text('Escolha o Serviço'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedServices.isNotEmpty)
                    _SelectedServicesHeader(services: _selectedServices),
                  _MultiSelectServicesFromSupabase(
                    initialSelectedIds:
                        _selectedServices.map((s) => s.id).toSet(),
                    onChange: (list) => setState(() => _selectedServices = list),
                  ),
                ],
              ),
            ),
            Step(
              isActive: _currentStep >= 1,
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
                  else
                    ..._barbers.map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _barberTile(
                          id: b.id,
                          name: b.name,
                          avatarUrl: b.avatarUrl,
                          rating: b.rating,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Step(
              isActive: _currentStep >= 2,
              title: const Text('Data e Horário'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined,
                        size: 16, color: _BP.gold),
                    label: Text(
                      _selectedDate == null
                          ? 'Selecionar data'
                          : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                      style: const TextStyle(color: _BP.gold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _BP.gold),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      final now = DateTime.now();
                      final date = await showDatePicker(
                        context: context,
                        locale: const Locale('pt', 'BR'),
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 60)),
                        initialDate: now,
                      );
                      if (date == null || !mounted) return;
                      setState(() => _selectedDate =
                          DateTime(date.year, date.month, date.day));
                      await _refreshSlots();
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_selectedBarberId == null)
                    const Text('Selecione um barbeiro no passo anterior.',
                        style: TextStyle(color: _BP.muted))
                  else if (_selectedDate == null)
                    const Text('Selecione uma data para ver os horários.',
                        style: TextStyle(color: _BP.muted))
                  else if (_availableSlots.isEmpty)
                    const Text('Sem horários disponíveis para este dia.',
                        style: TextStyle(color: _BP.muted))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableSlots.map((t) {
                        final label =
                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                        final taken = _takenSlots.contains(label);
                        final selected = _selectedTime == t;
                        return ChoiceChip(
                          label: Text(label),
                          selected: selected,
                          selectedColor: _BP.gold,
                          backgroundColor: _BP.card,
                          disabledColor: _BP.card.withValues(alpha: 0.4),
                          side: BorderSide(
                            color: selected ? _BP.gold : _BP.border,
                          ),
                          labelStyle: TextStyle(
                            color: selected
                                ? _BP.bg
                                : taken
                                    ? _BP.muted
                                    : _BP.text,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.normal,
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
            Step(
              isActive: _currentStep >= 3,
              title: const Text('Dados Pessoais'),
              content: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: _BP.text),
                    decoration: _inputDeco('Nome completo', Icons.person_outline),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: _BP.text),
                    inputFormatters: [
                      MaskTextInputFormatter(
                        mask: '(##) #####-####',
                        filter: {'#': RegExp(r'[0-9]')},
                      ),
                    ],
                    decoration: _inputDeco('Telefone', Icons.phone_outlined)
                        .copyWith(hintText: '(00) 00000-0000'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barberTile({
    required String id,
    required String name,
    required String avatarUrl,
    required double rating,
  }) {
    final selected = _selectedBarberId == id;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        setState(() => _selectedBarberId = id);
        await _refreshSlots();
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
              child: Text(
                name,
                style: const TextStyle(
                  color: _BP.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _BP.gold, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader({required this.service});
  final Service service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(51)),
      ),
      child: Row(
        children: [
          Icon(Icons.content_cut, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(service.formattedPrice, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedServicesHeader extends StatelessWidget {
  const _SelectedServicesHeader({required this.services});
  final List<Service> services;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _BP.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _BP.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.content_cut_rounded, color: _BP.gold, size: 16),
              SizedBox(width: 8),
              Text(
                'Serviços selecionados',
                style: TextStyle(
                  color: _BP.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: services
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _BP.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _BP.gold.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        s.name,
                        style: const TextStyle(
                          color: _BP.gold,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SelectServiceFromSupabase extends StatefulWidget {
  const _SelectServiceFromSupabase({required this.onSelect});
  final void Function(Service) onSelect;

  @override
  State<_SelectServiceFromSupabase> createState() =>
      __SelectServiceFromSupabaseState();
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
            }).toList(),
          ],
        );
      },
    );
  }
}

class __SelectServiceFromSupabaseState
    extends State<_SelectServiceFromSupabase> {
  late final Future<List<Service>> _servicesFuture;

  @override
  void initState() {
    super.initState();
    _servicesFuture = _fetchServices();
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
            const Text('Selecione um serviço abaixo:'),
            const SizedBox(height: 8),
            ...services.map(
              (s) => ListTile(
                leading: const Icon(Icons.content_cut),
                title: Text(s.name),
                subtitle: Text(s.formattedPrice),
                onTap: () => widget.onSelect(s),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Paleta dark (igual ao home) ───────────────────────────────────────────────

class _BP {
  static const Color bg     = Color(0xFF0C0D10);
  static const Color card   = Color(0xFF14161A);
  static const Color border = Color(0xFF252830);
  static const Color gold   = Color(0xFFF5C440);
  static const Color text   = Color(0xFFF0EDE8);
  static const Color muted  = Color(0xFF6B7280);
}

String _formatDateTime(DateTime dt) {
  final f = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  return f.format(dt);
}
