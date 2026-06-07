import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:barbearia/screens/admin/agenda_dia_view.dart';

enum _Period { day, month, year }

class AppointmentsAdminScreen extends StatefulWidget {
  const AppointmentsAdminScreen({super.key});

  @override
  State<AppointmentsAdminScreen> createState() =>
      _AppointmentsAdminScreenState();
}

class _AppointmentsAdminScreenState extends State<AppointmentsAdminScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _appointments = [];
  _Period _period = _Period.day;
  DateTime _selected = DateTime.now();
  String? _barberId;
  List<Map<String, dynamic>> _barbers = [];

  Future<void> _openWhatsApp(
    String phone,
    String barberName,
    String scheduledLabel,
  ) async {
    var digits = phone.replaceAll(RegExp(r'\\D'), '');
    if (digits.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Telefone inválido')));
      return;
    }
    if (!digits.startsWith('55')) digits = '55$digits';
    final hour = DateTime.now().hour;
    final prefix = hour < 12
        ? 'Bom dia'
        : hour < 18
        ? 'Boa tarde'
        : 'Boa noite';
    final msg = Uri.encodeComponent(
      '$prefix, passando só para confirmar o seu agendamento $scheduledLabel com o $barberName. Posso confirmar?',
    );
    try {
      final u = Uri.parse('whatsapp://send?phone=$digits&text=$msg');
      final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    for (final u in [
      Uri.parse('https://api.whatsapp.com/send?phone=$digits&text=$msg'),
      Uri.parse('https://wa.me/$digits?text=$msg'),
    ]) {
      try {
        final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {}
    }
    try {
      final last = Uri.parse('https://wa.me/$digits?text=$msg');
      final ok = await launchUrl(last, mode: LaunchMode.platformDefault);
      if (ok) return;
    } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Não foi possível abrir o WhatsApp. Verifique se está instalado.',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadBarbers();
    _load();
  }

  Future<void> _loadBarbers() async {
    try {
      final rows = await Supabase.instance.client
          .from('barbers')
          .select('id,name')
          .order('name');
      if (!mounted) return;
      setState(() {
        _barbers = List<Map<String, dynamic>>.from(rows);
      });
    } catch (_) {}
  }

  DateTime _startOfPeriod(DateTime d) {
    switch (_period) {
      case _Period.day:
        return DateTime(d.year, d.month, d.day);
      case _Period.month:
        return DateTime(d.year, d.month, 1);
      case _Period.year:
        return DateTime(d.year, 1, 1);
    }
  }

  DateTime _endOfPeriod(DateTime d) {
    switch (_period) {
      case _Period.day:
        return DateTime(d.year, d.month, d.day).add(const Duration(days: 1));
      case _Period.month:
        return DateTime(d.year, d.month + 1, 1);
      case _Period.year:
        return DateTime(d.year + 1, 1, 1);
    }
  }

  String _appointmentDateTime(Map<String, dynamic> appointment) {
    final legacy = appointment['date_time']?.toString();
    if (legacy != null && legacy.isNotEmpty) return legacy;

    final date = appointment['appointment_date']?.toString() ?? '';
    final time = appointment['appointment_time']?.toString() ?? '00:00:00';
    if (date.isEmpty) return appointment['created_at']?.toString() ?? '';
    return '${date}T$time';
  }

  String _dateOnly(String dateTime) {
    final dt = DateTime.tryParse(dateTime);
    if (dt != null) return DateFormat('yyyy-MM-dd').format(dt);
    return dateTime.split('T').first.split(' ').first;
  }

  String _timeOnly(String dateTime) {
    final dt = DateTime.tryParse(dateTime);
    if (dt != null) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:00';
    }
    final raw = dateTime.contains('T')
        ? dateTime.split('T').last
        : dateTime.split(' ').length > 1
        ? dateTime.split(' ')[1]
        : '00:00:00';
    final parts = raw.split(':');
    if (parts.length < 2) return '00:00:00';
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:00';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      dynamic rows;
      try {
        rows = await Supabase.instance.client
            .from('appointments')
            .select('''
              *,
              users:user_id(name, email, phone),
              barbers:barber_id(name),
              services:service_id(id, name)
            ''')
            .order('created_at', ascending: false);
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('oauth_client_id')) {
          try {
            await Supabase.instance.client.auth.signOut();
            rows = await Supabase.instance.client
                .from('appointments')
                .select('''
                  *,
                  users:user_id(name, email, phone),
                  barbers:barber_id(name),
                  services:service_id(id, name)
                ''')
                .order('created_at', ascending: false);
          } catch (_) {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      final list = List<Map<String, dynamic>>.from(rows);
      final groups = <String, Map<String, dynamic>>{};
      for (final a in list) {
        String userName = '';
        String userEmail = '';
        final usersRaw = a['users'];
        if (usersRaw is Map) {
          userName = usersRaw['name']?.toString() ?? '';
          userEmail = usersRaw['email']?.toString() ?? '';
        } else if (usersRaw is List && usersRaw.isNotEmpty) {
          final first = usersRaw.first;
          if (first is Map) {
            userName = first['name']?.toString() ?? '';
            userEmail = first['email']?.toString() ?? '';
          }
        }
        final customerName = (a['customer_name']?.toString() ?? '').trim();
        if (customerName.isNotEmpty) {
          userName = customerName;
        }
        final userPhoneFromUser = usersRaw is Map
            ? (usersRaw['phone']?.toString() ?? '')
            : '';
        final userPhone = (a['customer_phone']?.toString() ?? '').isNotEmpty
            ? (a['customer_phone']?.toString() ?? '')
            : userPhoneFromUser;
        final barberId = (a['barber_id'] ?? '').toString();
        String barberName = '';
        final barberRaw = a['barbers'];
        if (barberRaw is Map) {
          barberName = barberRaw['name']?.toString() ?? '';
        } else if (barberRaw is List && barberRaw.isNotEmpty) {
          final first = barberRaw.first;
          if (first is Map) {
            barberName = first['name']?.toString() ?? '';
          }
        }
        final scheduledAt = _appointmentDateTime(a);
        final servicesSet = <String>{};
        final servicesItems = <Map<String, dynamic>>[];
        final servicesRaw = a['services'];
        if (servicesRaw is Map) {
          final sid = servicesRaw['id']?.toString() ?? '';
          final sname = servicesRaw['name']?.toString() ?? '';
          servicesSet.add('$sid|$sname');
          servicesItems.add({'id': sid, 'name': sname});
        } else if (servicesRaw is List && servicesRaw.isNotEmpty) {
          for (final s in servicesRaw) {
            if (s is Map) {
              final sid = s['id']?.toString() ?? '';
              final sname = s['name']?.toString() ?? '';
              servicesSet.add('$sid|$sname');
              servicesItems.add({'id': sid, 'name': sname});
            }
          }
        }
        final key = '${userName}|${barberId}|${scheduledAt}';
        final existing = groups[key];
        if (existing == null) {
          groups[key] = {
            'user_name': userName,
            'user_email': userEmail,
            'user_phone': userPhone,
            'customer_id': (a['user_id']?.toString() ?? ''),
            'barber_name': barberName,
            'barber_id': barberId,
            'date_time': scheduledAt,
            'created_at': a['created_at']?.toString() ?? '',
            'status': (a['status']?.toString() ?? '').toLowerCase(),
            'attended_at': a['attended_at']?.toString() ?? '',
            'services': servicesSet.isEmpty ? <String>{} : servicesSet,
            'services_items': servicesItems,
          };
        } else {
          final exSet = (existing['services'] as Set<String>);
          for (final it in servicesItems) {
            final sid = it['id']?.toString() ?? '';
            final sname = it['name']?.toString() ?? '';
            if (sid.isNotEmpty || sname.isNotEmpty) {
              exSet.add('$sid|$sname');
            }
          }
          final exItems = List<Map<String, dynamic>>.from(
            existing['services_items'] as List? ?? const [],
          );
          exItems.addAll(servicesItems);
          existing['services_items'] = exItems;

          final currentStatus = (existing['status']?.toString() ?? '')
              .trim()
              .toLowerCase();
          final newStatus = (a['status']?.toString() ?? '')
              .trim()
              .toLowerCase();
          final hasAttended = (a['attended_at']?.toString() ?? '')
              .trim()
              .isNotEmpty;

          if (hasAttended) {
            existing['attended_at'] = a['attended_at']?.toString() ?? '';
            existing['status'] = 'attended';
          } else if (newStatus.isNotEmpty) {
            final isCancelled =
                newStatus == 'cancelled' ||
                newStatus == 'canceled' ||
                newStatus == 'cancel' ||
                newStatus.contains('cancel');
            final isNoShow = newStatus == 'no_show';
            if (currentStatus != 'attended') {
              if (isCancelled) {
                existing['status'] = 'cancelled';
              } else if (isNoShow) {
                existing['status'] = 'no_show';
              } else if (currentStatus.isEmpty) {
                existing['status'] = newStatus;
              }
            }
          }
        }
      }
      final aggregated = groups.values.map((g) {
        final set = (g['services'] as Set<String>);
        final list = set
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.split('|').length > 1 ? s.split('|')[1] : s)
            .toList();
        final ids = set
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.split('|').first)
            .where((id) => id.trim().isNotEmpty)
            .toList();
        return {
          'user_name': g['user_name'],
          'user_email': g['user_email'],
          'user_phone': g['user_phone'],
          'customer_id': g['customer_id'] ?? '',
          'barber_name': g['barber_name'],
          'barber_id': g['barber_id'],
          'date_time': g['date_time'],
          'created_at': g['created_at'],
          'status': g['status'] ?? '',
          'attended_at': g['attended_at'] ?? '',
          'services_text': list.join(', '),
          'services_list': list,
          'service_ids_list': ids,
          'services_items': g['services_items'] ?? const [],
        };
      }).toList();
      final start = _startOfPeriod(_selected);
      final end = _endOfPeriod(_selected);
      final filtered = aggregated.where((g) {
        final bid = (g['barber_id']?.toString() ?? '');
        final barberOk =
            _barberId == null || _barberId!.isEmpty || bid == _barberId;
        final raw = (g['date_time']?.toString() ?? '').trim();
        final createdRaw = (g['created_at']?.toString() ?? '').trim();
        final dt = DateTime.tryParse(raw) ?? DateTime.tryParse(createdRaw);
        if (dt == null) return barberOk;
        final afterStart = !dt.isBefore(start);
        final beforeEnd = dt.isBefore(end);
        return barberOk && afterStart && beforeEnd;
      }).toList();
      setState(() {
        _appointments = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<bool> _updateAppointmentsForGroup({
    required String barberId,
    required String scheduledAt,
    required Map<String, dynamic> data,
    String? customerName,
    String? customerPhone,
    String? customerId,
    List<String>? serviceIds,
  }) async {
    try {
      var query = Supabase.instance.client
          .from('appointments')
          .update(data)
          .eq('barber_id', barberId)
          .eq('appointment_date', _dateOnly(scheduledAt))
          .eq('appointment_time', _timeOnly(scheduledAt));
      final cid = (customerId ?? '').trim();
      if (cid.isNotEmpty) {
        query = query.eq('user_id', cid);
      } else {
        final cn = (customerName ?? '').trim();
        final cp = (customerPhone ?? '').trim();
        if (cn.isNotEmpty) query = query.eq('customer_name', cn);
        if (cp.isNotEmpty) query = query.eq('customer_phone', cp);
      }
      if (serviceIds != null && serviceIds.isNotEmpty) {
        final ors = serviceIds.map((id) => 'service_id.eq.$id').join(',');
        query = query.or(ors);
      }
      await query;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Salvo')));
      }
      return true;
    } catch (e) {
      final msg = e.toString();
      String? missing;
      final re1 = RegExp(
        r"column (?:appointments\.)?(\w+) does not exist",
        caseSensitive: false,
      );
      final re2 = RegExp(
        r"Could not find the '(\w+)' column of 'appointments'",
        caseSensitive: false,
      );
      final re3 = RegExp(
        r'column "(?:appointments\.)?(\w+)" does not exist',
        caseSensitive: false,
      );
      final m1 = re1.firstMatch(msg);
      final m2 = re2.firstMatch(msg);
      if (m1 != null) missing = m1.group(1);
      if (m2 != null) missing = m2.group(1);
      final m3 = re3.firstMatch(msg);
      if (m3 != null) missing = m3.group(1);
      if (mounted) {
        if (missing != null && missing.isNotEmpty) {
          _showSchemaHelp(missing);
          if (data.containsKey(missing)) {
            final retry = Map<String, dynamic>.from(data)..remove(missing);
            try {
              var q2 = Supabase.instance.client
                  .from('appointments')
                  .update(retry)
                  .eq('barber_id', barberId)
                  .eq('appointment_date', _dateOnly(scheduledAt))
                  .eq('appointment_time', _timeOnly(scheduledAt));
              final cid2 = (customerId ?? '').trim();
              if (cid2.isNotEmpty) {
                q2 = q2.eq('user_id', cid2);
              } else {
                final cn2 = (customerName ?? '').trim();
                final cp2 = (customerPhone ?? '').trim();
                if (cn2.isNotEmpty) q2 = q2.eq('customer_name', cn2);
                if (cp2.isNotEmpty) q2 = q2.eq('customer_phone', cp2);
              }
              if (serviceIds != null && serviceIds.isNotEmpty) {
                final ors = serviceIds
                    .map((id) => 'service_id.eq.$id')
                    .join(',');
                q2 = q2.or(ors);
              }
              await q2;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Salvo (parcial)')));
              return true;
            } catch (_) {}
          }
        } else {
          final violates = RegExp(
            r"violates check constraint[\s\S]*appointments_status_check",
            caseSensitive: false,
          );
          if (violates.hasMatch(msg) && data.containsKey('status')) {
            final currentStatus = '${data['status']}'.toLowerCase();
            final alternatives = <String>[
              if (currentStatus == 'cancelled') 'canceled',
              if (currentStatus == 'canceled') 'cancelled',
              if (currentStatus == 'no_show') ...['no-show', 'noshow'],
            ];
            for (final alt in alternatives) {
              try {
                final fix = Map<String, dynamic>.from(data)..['status'] = alt;
                var q3 = Supabase.instance.client
                    .from('appointments')
                    .update(fix)
                    .eq('barber_id', barberId)
                    .eq('appointment_date', _dateOnly(scheduledAt))
                    .eq('appointment_time', _timeOnly(scheduledAt));
                final cid3 = (customerId ?? '').trim();
                if (cid3.isNotEmpty) {
                  q3 = q3.eq('user_id', cid3);
                } else {
                  final cn3 = (customerName ?? '').trim();
                  final cp3 = (customerPhone ?? '').trim();
                  if (cn3.isNotEmpty) q3 = q3.eq('customer_name', cn3);
                  if (cp3.isNotEmpty) q3 = q3.eq('customer_phone', cp3);
                }
                if (serviceIds != null && serviceIds.isNotEmpty) {
                  final ors = serviceIds
                      .map((id) => 'service_id.eq.$id')
                      .join(',');
                  q3 = q3.or(ors);
                }
                await q3;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Salvo')));
                return true;
              } catch (_) {}
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Erro: status inválido para tabela'),
              ),
            );
            return false;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erro: $e')));
        }
      }
      return false;
    }
  }

  void _showSchemaHelp(String missing) {
    final sql = [
      "ALTER TABLE appointments ADD COLUMN IF NOT EXISTS status text DEFAULT 'scheduled';",
      "ALTER TABLE appointments ADD COLUMN IF NOT EXISTS attended_at timestamptz;",
      "ALTER TABLE appointments ADD COLUMN IF NOT EXISTS performed_service_ids text[] DEFAULT '{}'::text[];",
    ].join("\n");
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Configurar colunas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Faltou a coluna: $missing'),
                const SizedBox(height: 8),
                const Text('Execute no Supabase (Editor SQL):'),
                const SizedBox(height: 8),
                SelectableText(sql),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Ok'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _markAttended({
    required String barberId,
    required String scheduledAt,
    String? customerName,
    String? customerPhone,
    String? customerId,
    List<String>? serviceIds,
  }) async {
    final ok = await _updateAppointmentsForGroup(
      barberId: barberId,
      scheduledAt: scheduledAt,
      data: {
        'status': 'attended',
        'attended_at': DateTime.now().toIso8601String(),
      },
      customerName: customerName,
      customerPhone: customerPhone,
      customerId: customerId,
      serviceIds: serviceIds,
    );
    if (ok) await _load();
  }

  Future<void> _markNoShow({
    required String barberId,
    required String scheduledAt,
    String? customerName,
    String? customerPhone,
    String? customerId,
    List<String>? serviceIds,
  }) async {
    final ok = await _updateAppointmentsForGroup(
      barberId: barberId,
      scheduledAt: scheduledAt,
      data: {'status': 'no_show', 'attended_at': null},
      customerName: customerName,
      customerPhone: customerPhone,
      customerId: customerId,
      serviceIds: serviceIds,
    );
    if (ok) await _load();
  }

  Future<void> _cancelAppointment({
    required String barberId,
    required String scheduledAt,
    String? customerName,
    String? customerPhone,
    String? customerId,
    List<String>? serviceIds,
  }) async {
    final ok = await _updateAppointmentsForGroup(
      barberId: barberId,
      scheduledAt: scheduledAt,
      data: {'status': 'cancelled', 'attended_at': null},
      customerName: customerName,
      customerPhone: customerPhone,
      customerId: customerId,
      serviceIds: serviceIds,
    );
    if (ok) await _load();
  }

  Future<bool> _editPerformedServices({
    required String barberId,
    required String scheduledAt,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerPhone,
  }) async {
    List<Map<String, dynamic>> all;
    try {
      final rows = await Supabase.instance.client
          .from('services')
          .select('id, name')
          .order('name');
      all = List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      all = items;
    }
    final ids = all.map((e) => e['id']?.toString() ?? '').toList();
    final names = all.map((e) => e['name']?.toString() ?? '').toList();
    final initialSel = items
        .map((e) => e['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final current = ValueNotifier<Set<String>>(initialSel);
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirmar serviço realizado'),
          content: SizedBox(
            width: double.maxFinite,
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.builder(
                    itemCount: ids.length,
                    itemBuilder: (ctx2, i) {
                      final id = ids[i];
                      final name = names[i];
                      final sel = current.value.contains(id);
                      return CheckboxListTile(
                        value: sel,
                        title: Text(name.isEmpty ? 'Serviço' : name),
                        onChanged: (v) {
                          setStateDialog(() {
                            final s = current.value;
                            if (v == true) {
                              s.add(id);
                            } else {
                              s.remove(id);
                            }
                            current.value = Set<String>.from(s);
                          });
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, current.value.toList()),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
    if (selected != null) {
      final ok = await _updateAppointmentsForGroup(
        barberId: barberId,
        scheduledAt: scheduledAt,
        data: {'performed_service_ids': selected},
        customerName: customerName,
        customerPhone: customerPhone,
        serviceIds: items
            .map((e) => e['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(),
      );
      return ok;
    }
    return false;
  }

  Future<void> _openAppointmentActions({
    required String barberId,
    required String scheduledAt,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerPhone,
    String? customerId,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        bool done = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Ações do agendamento'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Primeiro: confirmar serviços realizados
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await _editPerformedServices(
                          barberId: barberId,
                          scheduledAt: scheduledAt,
                          items: items,
                          customerName: customerName,
                          customerPhone: customerPhone,
                        );
                        setStateDialog(() => done = ok);
                      },
                      icon: const Icon(Icons.checklist_rtl),
                      label: Text(
                        done
                            ? 'Serviços confirmados'
                            : 'Confirmar serviço realizado',
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Depois: presença (habilitado só após confirmar serviços)
                    FilledButton.icon(
                      onPressed: done
                          ? () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (cnf) {
                                  return AlertDialog(
                                    title: const Text('Confirmar'),
                                    content: const Text(
                                      'Marcar como compareceu?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(cnf, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(cnf, true),
                                        child: const Text('Confirmar'),
                                      ),
                                    ],
                                  );
                                },
                              );
                              if (ok == true) {
                                Navigator.pop(ctx);
                                await _markAttended(
                                  barberId: barberId,
                                  scheduledAt: scheduledAt,
                                  customerName: customerName,
                                  customerPhone: customerPhone,
                                  customerId: customerId,
                                  serviceIds: items
                                      .map((e) => e['id']?.toString() ?? '')
                                      .where((id) => id.isNotEmpty)
                                      .toList(),
                                );
                              }
                            }
                          : null,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Compareceu'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () async {
                        final choice = await showDialog<String>(
                          context: context,
                          builder: (cnf) {
                            return AlertDialog(
                              title: const Text('Confirmar'),
                              content: const Text(
                                'Deseja marcar como não compareceu ou cancelar o agendamento?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(cnf, 'cancel'),
                                  child: const Text('Cancelar agendamento'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(cnf, 'no_show'),
                                  child: const Text('Não compareceu'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(cnf, null),
                                  child: const Text('Fechar'),
                                ),
                              ],
                            );
                          },
                        );
                        if (choice == 'cancel' || choice == 'no_show') {
                          Navigator.pop(ctx);
                          if (choice == 'cancel') {
                            await _cancelAppointment(
                              barberId: barberId,
                              scheduledAt: scheduledAt,
                              customerName: customerName,
                              customerPhone: customerPhone,
                              customerId: customerId,
                              serviceIds: items
                                  .map((e) => e['id']?.toString() ?? '')
                                  .where((id) => id.isNotEmpty)
                                  .toList(),
                            );
                          } else {
                            await _markNoShow(
                              barberId: barberId,
                              scheduledAt: scheduledAt,
                              customerName: customerName,
                              customerPhone: customerPhone,
                              customerId: customerId,
                              serviceIds: items
                                  .map((e) => e['id']?.toString() ?? '')
                                  .where((id) => id.isNotEmpty)
                                  .toList(),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Não compareceu / Cancelar'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final initial = _selected;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
      initialDatePickerMode: _period == _Period.year
          ? DatePickerMode.year
          : DatePickerMode.day,
    );
    if (d != null) {
      setState(() => _selected = d);
      await _load();
    }
  }

  String get _periodLabel {
    switch (_period) {
      case _Period.day:
        return DateFormat.yMMMMd('pt_BR').format(_selected);
      case _Period.month:
        return DateFormat.yMMMM('pt_BR').format(_selected);
      case _Period.year:
        return DateFormat.y('pt_BR').format(_selected);
    }
  }

  // Status removido

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Agendamentos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Erro: $_error'))
          : RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _period = _Period.day;
                  _selected = DateTime.now();
                  _barberId = null;
                });
                await _load();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            DropdownButton<_Period>(
                              value: _period,
                              items: const [
                                DropdownMenuItem<_Period>(
                                  value: _Period.day,
                                  child: Text('Dia'),
                                ),
                                DropdownMenuItem<_Period>(
                                  value: _Period.month,
                                  child: Text('Mês'),
                                ),
                                DropdownMenuItem<_Period>(
                                  value: _Period.year,
                                  child: Text('Ano'),
                                ),
                              ],
                              onChanged: (p) async {
                                if (p == null) return;
                                setState(() => _period = p);
                                await _load();
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _periodLabel,
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _pickDate,
                              icon: const Icon(Icons.edit_calendar),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButton<String?>(
                                value: _barberId,
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Todos os barbeiros'),
                                  ),
                                  ..._barbers.map(
                                    (b) => DropdownMenuItem<String?>(
                                      value: b['id']?.toString(),
                                      child: Text(b['name']?.toString() ?? ''),
                                    ),
                                  ),
                                ],
                                onChanged: (v) async {
                                  setState(() => _barberId = v);
                                  await _load();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_period == _Period.day)
                    AgendaDiaView(
                      date: _selected,
                      barberId: _barberId,
                      barbers: _barbers,
                    ),
                  if (_period != _Period.day && _appointments.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outline.withAlpha(40),
                        ),
                      ),
                      child: Text(
                        'Nenhum agendamento neste período.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  if (_period != _Period.day)
                    ...List.generate(_appointments.length, (index) {
                    final a = _appointments[index];
                    final theme = Theme.of(context);
                    final userName = (a['user_name']?.toString() ?? '').trim();
                    final userPhone = (a['user_phone']?.toString() ?? '')
                        .trim();
                    final barberName = (a['barber_name']?.toString() ?? '')
                        .trim();
                    final servicesText = (a['services_text']?.toString() ?? '')
                        .trim();
                    final userEmail = (a['user_email']?.toString() ?? '')
                        .trim();
                    final servicesListDynamic = a['services_list'];
                    final servicesList = servicesListDynamic is List
                        ? servicesListDynamic.map((e) => e.toString()).toList()
                        : <String>[];
                    final scheduledRaw = (a['date_time']?.toString() ?? '')
                        .trim();
                    final scheduledDt = DateTime.tryParse(scheduledRaw);
                    final scheduledLabel = scheduledDt == null
                        ? ''
                        : DateFormat(
                            'dd/MM/yyyy HH:mm',
                            'pt_BR',
                          ).format(scheduledDt);
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.outline.withAlpha(40),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName.isEmpty ? 'Cliente' : userName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (userEmail.isNotEmpty)
                                  Text(
                                    userEmail,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                if (scheduledLabel.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.schedule, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          scheduledLabel,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.person, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'agendou com $barberName',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.content_cut, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Serviços: $servicesText',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.call, size: 16),
                                const SizedBox(width: 6),
                                if (userPhone.isEmpty)
                                  Text(
                                    'Sem telefone',
                                    style: theme.textTheme.bodyMedium,
                                  )
                                else
                                  InkWell(
                                    onTap: () => _openWhatsApp(
                                      userPhone,
                                      barberName,
                                      scheduledLabel,
                                    ),
                                    child: Text(
                                      userPhone,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                    ),
                                  ),
                                if (userPhone.isNotEmpty)
                                  const SizedBox(width: 12),
                                if (userPhone.isNotEmpty)
                                  InkWell(
                                    onTap: () => _openWhatsApp(
                                      userPhone,
                                      barberName,
                                      scheduledLabel,
                                    ),
                                    child: Row(
                                      children: [
                                        FaIcon(
                                          FontAwesomeIcons.whatsapp,
                                          size: 16,
                                          color: const Color(0xFF25D366),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'WhatsApp',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Builder(
                              builder: (context) {
                                final statusRaw =
                                    (a['status']?.toString() ?? '')
                                        .trim()
                                        .toLowerCase();
                                final attendedRaw =
                                    (a['attended_at']?.toString() ?? '').trim();
                                final isAttended = attendedRaw.isNotEmpty;
                                final isNoShow = statusRaw == 'no_show';
                                final isCancelled =
                                    statusRaw == 'cancelled' ||
                                    statusRaw == 'canceled' ||
                                    statusRaw == 'cancel' ||
                                    statusRaw.contains('cancel');
                                final isNoShowAlt =
                                    statusRaw == 'noshow' ||
                                    statusRaw == 'no-show' ||
                                    statusRaw.replaceAll(' ', '_') == 'no_show';
                                if (isAttended) {
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: Chip(
                                      label: const Text('Compareceu'),
                                      backgroundColor:
                                          theme.colorScheme.primaryContainer,
                                      labelStyle: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onPrimaryContainer,
                                          ),
                                    ),
                                  );
                                } else if (isNoShow || isNoShowAlt) {
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: Chip(
                                      label: const Text('Não compareceu'),
                                      backgroundColor:
                                          theme.colorScheme.surfaceVariant,
                                    ),
                                  );
                                } else if (isCancelled) {
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: Chip(
                                      label: const Text(
                                        'Agendamento cancelado',
                                      ),
                                      backgroundColor:
                                          theme.colorScheme.surfaceVariant,
                                    ),
                                  );
                                }
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton.icon(
                                    onPressed: () => _openAppointmentActions(
                                      barberId:
                                          (a['barber_id']?.toString() ?? ''),
                                      scheduledAt: scheduledRaw,
                                      items: List<Map<String, dynamic>>.from(
                                        a['services_items'] ?? const [],
                                      ),
                                      customerName: userName,
                                      customerPhone: userPhone,
                                      customerId:
                                          (a['customer_id']?.toString() ?? ''),
                                    ),
                                    icon: const Icon(Icons.more_horiz),
                                    label: const Text('Ações'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
