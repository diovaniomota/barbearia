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
  double _planTotal = 0.0;
  int _planCount = 0;

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
        _planTotal = 0.0;
        _planCount = 0;
      });
    }
    try {
      final supabase = Supabase.instance.client;
      final startDate = DateFormat(
        'yyyy-MM-dd',
      ).format(_startOfPeriod(_selected));
      final endDate = DateFormat('yyyy-MM-dd').format(_endOfPeriod(_selected));

      var query = supabase
          .from('appointments')
          .select(
            'appointment_date, appointment_time, status, is_plan_client, '
            'barber_id, customer_phone, total_price, '
            'barbers:barber_id(name), services:service_id(id, name, price)',
          )
          .gte('appointment_date', startDate)
          .lt('appointment_date', endDate);

      if (_barberId != null && _barberId!.isNotEmpty) {
        query = query.eq('barber_id', _barberId!);
      }

      final rows = await query.order('appointment_date', ascending: true);
      final list = List<Map<String, dynamic>>.from(rows);

      final byBarber = <String, _FinanceRow>{};
      // Telefones normalizados (só dígitos) de clientes plano com atendimento
      // no período — usado depois para buscar monthly_value em plan_clients.
      final planPhones = <String>{};
      double total = 0.0;
      final now = DateTime.now();
      for (final r in list) {
        final status = (r['status']?.toString() ?? '').toLowerCase();
        if (status == 'no_show' ||
            status == 'cancelled' ||
            status == 'canceled') {
          continue;
        }
        // Só contabiliza se o horário já passou
        final ds = r['appointment_date']?.toString() ?? '';
        final ts = (r['appointment_time']?.toString() ?? '').split(':');
        if (ds.isEmpty) continue;
        try {
          final dp = ds.split('-');
          final apptDt = DateTime(
            int.parse(dp[0]),
            int.parse(dp[1]),
            int.parse(dp[2]),
            ts.isNotEmpty ? int.tryParse(ts[0]) ?? 0 : 0,
            ts.length > 1 ? int.tryParse(ts[1]) ?? 0 : 0,
          );
          if (apptDt.isAfter(now)) continue;
        } catch (_) {
          continue;
        }

        // Cliente do plano: registra o telefone para calcular mensalidade.
        // Não entra na receita avulsa.
        if (r['is_plan_client'] == true) {
          final phone = (r['customer_phone']?.toString() ?? '')
              .replaceAll(RegExp(r'[^0-9]'), '');
          if (phone.isNotEmpty) planPhones.add(phone);
          continue;
        }

        // Usa total_price para evitar dupla contagem de serviços multi-bloco
        // (ex: Nevada = 2 blocos de 30 min — só o 1º bloco tem total_price > 0).
        double price = 0.0;
        final tp = r['total_price'] as num?;
        if (tp != null) {
          price = tp.toDouble();
        } else {
          // Fallback para agendamentos antigos sem total_price
          final servicesRaw = r['services'];
          if (servicesRaw is Map) {
            price = (servicesRaw['price'] as num?)?.toDouble() ?? 0.0;
          } else if (servicesRaw is List) {
            for (final s in servicesRaw) {
              if (s is Map) {
                final p = s['price'] as num?;
                if (p != null) price += p.toDouble();
              }
            }
          }
        }

        total += price;
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

      // Mensalidades: soma monthly_value de cada cliente plano distinto
      // que teve atendimento no período (uma vez por cliente, independente
      // de quantas visitas fez).
      double planTotal = 0.0;
      int planCount = 0;
      if (planPhones.isNotEmpty) {
        try {
          final allPlanClients = await supabase
              .from('plan_clients')
              .select('phone, monthly_value');
          final seenDigits = <String>{};
          for (final pc in List<Map<String, dynamic>>.from(allPlanClients)) {
            final digits = (pc['phone']?.toString() ?? '')
                .replaceAll(RegExp(r'[^0-9]'), '');
            if (digits.isNotEmpty &&
                planPhones.contains(digits) &&
                !seenDigits.contains(digits)) {
              seenDigits.add(digits);
              planTotal += (pc['monthly_value'] as num?)?.toDouble() ?? 0.0;
              planCount++;
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _rows = byBarber.values.toList()
          ..sort((a, b) => b.total.compareTo(a.total));
        _total = total;
        _planTotal = planTotal;
        _planCount = planCount;
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
          final startDate = DateFormat(
            'yyyy-MM-dd',
          ).format(_startOfPeriod(_selected));
          final endDate = DateFormat(
            'yyyy-MM-dd',
          ).format(_endOfPeriod(_selected));
          var q = supabase
              .from('appointments')
              .select(
                'appointment_date, appointment_time, status, barber_id, barbers:barber_id(name), services:service_id(id, name, price)',
              )
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
            if (status == 'no_show' ||
                status == 'cancelled' ||
                status == 'canceled') {
              continue;
            }
            final ds = r['appointment_date']?.toString() ?? '';
            final ts = (r['appointment_time']?.toString() ?? '').split(':');
            if (ds.isEmpty) continue;
            try {
              final dp = ds.split('-');
              final apptDt = DateTime(
                int.parse(dp[0]),
                int.parse(dp[1]),
                int.parse(dp[2]),
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
          if (mounted) {
            setState(() {
              _rows = byBarber.values.toList()
                ..sort((a, b) => b.total.compareTo(a.total));
              _total = total;
              _planTotal = 0.0;
              _planCount = 0;
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
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.0)),
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
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
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
                                        child: Text(
                                          b['name']?.toString() ?? '',
                                        ),
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
                          color: theme.colorScheme.outline.withValues(alpha: 0.2),
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
                  // Mensalidades dos clientes do plano (valor mensal, não por corte)
                  if (_planCount > 0)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFF5C200).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.card_membership_outlined,
                            color: Color(0xFFF5C200),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mensalidades',
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(
                                  '$_planCount cliente${_planCount != 1 ? 's' : ''} do plano',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            f.format(_planTotal),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: const Color(0xFFF5C200),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (_planCount > 0) ...[
                          Row(
                            children: [
                              Text(
                                'Avulsos',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                f.format(_total),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                'Plano',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                f.format(_planTotal),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Text(
                              'Total',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              f.format(_total + _planTotal),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
