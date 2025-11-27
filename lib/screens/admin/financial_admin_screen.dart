import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

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
      final start = _startOfPeriod(_selected).toIso8601String();
      final end = _endOfPeriod(_selected).toIso8601String();

      var query = supabase
          .from('appointments')
          .select(
            'created_at, attended_at, status, performed_service_ids, barber_id, barbers:barber_id(name), services:service_id(id, name, price)',
          )
          .gte('attended_at', start)
          .lt('attended_at', end);

      if (_barberId != null && _barberId!.isNotEmpty) {
        query = query.eq('barber_id', _barberId!);
      }

      final rows = await query.order('created_at', ascending: true);
      final list = List<Map<String, dynamic>>.from(rows);

      final byBarber = <String, _FinanceRow>{};
      double total = 0.0;
      for (final r in list) {
        final status = (r['status']?.toString() ?? '').toLowerCase();
        final attendedAtRaw = r['attended_at']?.toString();
        if (attendedAtRaw == null || attendedAtRaw.isEmpty) {
          // Não contabiliza sem atendido
          continue;
        }
        if (status.isNotEmpty && status != 'attended') {
          // Não contabiliza no-show ou outros
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
      if (!mounted) return;
      if (missing != null && missing.isNotEmpty) {
        // Tenta fallback para continuar funcionando
        try {
          final supabase = Supabase.instance.client;
          final start = _startOfPeriod(_selected).toIso8601String();
          final end = _endOfPeriod(_selected).toIso8601String();

          Future<List<Map<String, dynamic>>> runQuery({
            required bool byCreated,
            required bool includePerformed,
            required bool includeStatus,
            required bool filterStatus,
          }) async {
            var sel =
                'created_at, barber_id, barbers:barber_id(name), services:service_id(id, name, price)';
            if (includeStatus) sel = sel + ', status';
            if (includePerformed) sel = sel + ', performed_service_ids';
            var q = supabase.from('appointments').select(sel);
            if (byCreated) {
              q = q.gte('created_at', start).lt('created_at', end);
              if (filterStatus) q = q.eq('status', 'attended');
            } else {
              q = q.gte('attended_at', start).lt('attended_at', end);
            }
            if (_barberId != null && _barberId!.isNotEmpty) {
              q = q.eq('barber_id', _barberId!);
            }
            final rows = await q.order('created_at', ascending: true);
            return List<Map<String, dynamic>>.from(rows);
          }

          List<Map<String, dynamic>> list;
          if (missing == 'attended_at') {
            try {
              list = await runQuery(
                byCreated: true,
                includePerformed: true,
                includeStatus: true,
                filterStatus: true,
              );
            } catch (_) {
              try {
                list = await runQuery(
                  byCreated: true,
                  includePerformed: true,
                  includeStatus: false,
                  filterStatus: false,
                );
              } catch (_) {
                list = await runQuery(
                  byCreated: true,
                  includePerformed: false,
                  includeStatus: false,
                  filterStatus: false,
                );
              }
            }
          } else if (missing == 'performed_service_ids') {
            list = await runQuery(
              byCreated: false,
              includePerformed: false,
              includeStatus: true,
              filterStatus: true,
            );
          } else {
            // status ausente
            try {
              list = await runQuery(
                byCreated: false,
                includePerformed: true,
                includeStatus: true,
                filterStatus: true,
              );
            } catch (_) {
              list = await runQuery(
                byCreated: false,
                includePerformed: true,
                includeStatus: false,
                filterStatus: false,
              );
            }
          }

          final byBarber = <String, _FinanceRow>{};
          double total = 0.0;
          for (final r in list) {
            final status = (r['status']?.toString() ?? '').toLowerCase();
            if (missing != 'attended_at') {
              final attendedAtRaw = r['attended_at']?.toString();
              if (attendedAtRaw == null || attendedAtRaw.isEmpty) {
                continue;
              }
            } else {
              if (status.isNotEmpty && status != 'attended') continue;
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
          setState(() {
            _rows = byBarber.values.toList()
              ..sort((a, b) => b.total.compareTo(a.total));
            _total = total;
            _loading = false;
          });
          return;
        } catch (_) {
          if (mounted) {
            setState(() {
              _loading = false;
            });
          }
          _showSchemaHelp(missing);
        }
      } else {
        setState(() {
          _error = msg;
          _loading = false;
        });
      }
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
