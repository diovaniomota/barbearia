import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:barbearia/utils/admin_session.dart';

class FinancialAdminScreen extends StatefulWidget {
  const FinancialAdminScreen({super.key});

  @override
  State<FinancialAdminScreen> createState() => _FinancialAdminScreenState();
}

enum _Period { day, month, year }

class _FinancialAdminScreenState extends State<FinancialAdminScreen> {
  bool _loading = true;
  String? _error;
  _Period _period = _Period.day;
  DateTime _selected = DateTime.now();
  String? _barberId;
  List<Map<String, dynamic>> _barbers = [];
  List<_FinanceRow> _rows = [];
  double _total = 0.0;

  @override
  void initState() {
    super.initState();
    if (AdminSession.isBarber) _barberId = AdminSession.barberId;
    _loadBarbers();
    _loadFinance();
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

  Future<void> _loadFinance() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _rows = [];
        _total = 0.0;
      });
    }
    try {
      final supabase = Supabase.instance.client;
      final startDate = DateFormat('yyyy-MM-dd').format(_startOfPeriod(_selected));
      final endDate = DateFormat('yyyy-MM-dd').format(_endOfPeriod(_selected));

      var query = supabase
          .from('appointments')
          .select(
            'appointment_date, appointment_time, status, performed_service_ids, is_plan_client, barber_id, barbers:barber_id(name), services:service_id(id, name, price)',
          )
          .gte('appointment_date', startDate)
          .lt('appointment_date', endDate);

      if (_barberId != null && _barberId!.isNotEmpty) {
        query = query.eq('barber_id', _barberId!);
      }

      final rows = await query.order('appointment_date', ascending: true);
      final list = List<Map<String, dynamic>>.from(rows);

      final byBarber = <String, _FinanceRow>{};
      double total = 0.0;
      final now = DateTime.now();
      for (final r in list) {
        final status = (r['status']?.toString() ?? '').toLowerCase();
        // Exclui cancelados e não compareceu
        if (status == 'no_show' || status == 'cancelled' || status == 'canceled') continue;
        // Exclui clientes plano
        if (r['is_plan_client'] == true) continue;
        // Só contabiliza se o horário já passou
        final ds = r['appointment_date']?.toString() ?? '';
        final ts = (r['appointment_time']?.toString() ?? '').split(':');
        if (ds.isEmpty) continue;
        try {
          final dp = ds.split('-');
          final apptDt = DateTime(
            int.parse(dp[0]), int.parse(dp[1]), int.parse(dp[2]),
            ts.isNotEmpty ? int.tryParse(ts[0]) ?? 0 : 0,
            ts.length > 1 ? int.tryParse(ts[1]) ?? 0 : 0,
          );
          if (apptDt.isAfter(now)) continue;
        } catch (_) {
          continue;
        }
        final barberRaw = r['barbers'];
        String barberName = '';
        if (barberRaw is Map) {
          barberName = barberRaw['name']?.toString() ?? '';
        } else if (barberRaw is List && barberRaw.isNotEmpty) {
          final first = barberRaw.first;
          if (first is Map) {
            barberName = first['name']?.toString() ?? '';
          }
        }
        final barberId = (r['barber_id'] ?? '').toString();
        final servicesRaw = r['services'];
        final performed = <String>{};
        final performedRaw = r['performed_service_ids'];
        if (performedRaw is List) {
          for (final id in performedRaw) {
            performed.add(id.toString());
          }
        }
        double price = 0.0;
        if (servicesRaw is Map) {
          final id = servicesRaw['id']?.toString() ?? '';
          if (performed.isEmpty || performed.contains(id)) {
            final p = servicesRaw['price'] as num?;
            price = (p == null) ? 0.0 : p.toDouble();
          }
        } else if (servicesRaw is List) {
          for (final s in servicesRaw) {
            if (s is Map) {
              final id = s['id']?.toString() ?? '';
              if (performed.isEmpty || performed.contains(id)) {
                final p = s['price'] as num?;
                if (p != null) price += p.toDouble();
              }
            }
          }
        }
        total += price;
        final current = byBarber[barberId];
        if (current == null) {
          byBarber[barberId] = _FinanceRow(
            barberId: barberId,
            barberName: barberName,
            total: price,
          );
        } else {
          byBarber[barberId] = _FinanceRow(
            barberId: barberId,
            barberName: current.barberName,
            total: current.total + price,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _rows = byBarber.values.toList()
          ..sort((a, b) => b.total.compareTo(a.total));
        _total = total;
        _loading = false;
      });
    } catch (e) {
      final msg = e.toString();
      // Detecta coluna opcional faltando (performed_service_ids ou is_plan_client)
      // e retenta sem essas colunas opcionais
      final missingMatch = RegExp(
        r"column (?:appointments\.)?(\w+) does not exist|Could not find the '(\w+)' column",
        caseSensitive: false,
      ).firstMatch(msg);
      final missing = missingMatch?.group(1) ?? missingMatch?.group(2);

      if (missing == 'performed_service_ids' || missing == 'is_plan_client') {
        try {
          final supabase = Supabase.instance.client;
          final startDate = DateFormat('yyyy-MM-dd').format(_startOfPeriod(_selected));
          final endDate = DateFormat('yyyy-MM-dd').format(_endOfPeriod(_selected));
          var q = supabase
              .from('appointments')
              .select('appointment_date, appointment_time, status, barber_id, barbers:barber_id(name), services:service_id(id, name, price)')
              .gte('appointment_date', startDate)
              .lt('appointment_date', endDate);
          if (_barberId != null && _barberId!.isNotEmpty) {
            q = q.eq('barber_id', _barberId!);
          }
          final rows = await q.order('appointment_date', ascending: true);
          final list = List<Map<String, dynamic>>.from(rows);
          final byBarber = <String, _FinanceRow>{};
          double total = 0.0;
          final now = DateTime.now();
          for (final r in list) {
            final status = (r['status']?.toString() ?? '').toLowerCase();
            if (status == 'no_show' || status == 'cancelled' || status == 'canceled') continue;
            final ds = r['appointment_date']?.toString() ?? '';
            final ts = (r['appointment_time']?.toString() ?? '').split(':');
            if (ds.isEmpty) continue;
            try {
              final dp = ds.split('-');
              final apptDt = DateTime(
                int.parse(dp[0]), int.parse(dp[1]), int.parse(dp[2]),
                ts.isNotEmpty ? int.tryParse(ts[0]) ?? 0 : 0,
                ts.length > 1 ? int.tryParse(ts[1]) ?? 0 : 0,
              );
              if (apptDt.isAfter(now)) continue;
            } catch (_) {
              continue;
            }
            final barberRaw = r['barbers'];
            String barberName = '';
            if (barberRaw is Map) {
              barberName = barberRaw['name']?.toString() ?? '';
            } else if (barberRaw is List && barberRaw.isNotEmpty) {
              final first = barberRaw.first;
              if (first is Map) barberName = first['name']?.toString() ?? '';
            }
            final barberId = (r['barber_id'] ?? '').toString();
            final servicesRaw = r['services'];
            double price = 0.0;
            if (servicesRaw is Map) {
              final p = servicesRaw['price'] as num?;
              price = p?.toDouble() ?? 0.0;
            } else if (servicesRaw is List) {
              for (final s in servicesRaw) {
                if (s is Map) {
                  final p = s['price'] as num?;
                  if (p != null) price += p.toDouble();
                }
              }
            }
            total += price;
            final current = byBarber[barberId];
            if (current == null) {
              byBarber[barberId] = _FinanceRow(barberId: barberId, barberName: barberName, total: price);
            } else {
              byBarber[barberId] = _FinanceRow(barberId: barberId, barberName: current.barberName, total: current.total + price);
            }
          }
          if (mounted) {
            setState(() {
              _rows = byBarber.values.toList()..sort((a, b) => b.total.compareTo(a.total));
              _total = total;
              _loading = false;
            });
          }
          return;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _error = msg;
        _loading = false;
      });
    }
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child!,
      ),
    );
    if (d != null) {
      setState(() => _selected = d);
      await _loadFinance();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Scaffold(
      appBar: AppBar(title: const Text('Caixa')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Erro: $_error'))
          : RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _period = _Period.day;
                  _selected = DateTime.now();
                });
                await _loadFinance();
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
                                DropdownMenuItem(
                                  value: _Period.day,
                                  child: Text('Dia'),
                                ),
                                DropdownMenuItem(
                                  value: _Period.month,
                                  child: Text('Mês'),
                                ),
                                DropdownMenuItem(
                                  value: _Period.year,
                                  child: Text('Ano'),
                                ),
                              ],
                              onChanged: (p) async {
                                if (p == null) return;
                                setState(() => _period = p);
                                await _loadFinance();
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
                        if (!AdminSession.isBarber)
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
                                    await _loadFinance();
                                  },
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._rows.map(
                    (r) => Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              r.barberName.isEmpty ? 'Sem nome' : r.barberName,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            f.format(r.total),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Total',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          f.format(_total),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
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
}

class _FinanceRow {
  final String barberId;
  final String barberName;
  final double total;
  const _FinanceRow({
    required this.barberId,
    required this.barberName,
    required this.total,
  });
}
