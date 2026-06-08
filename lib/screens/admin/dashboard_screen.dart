import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:barbearia/utils/admin_session.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  int _barbers = 0;
  int _services = 0;
  int _appointments = 0;
  List<_Slice> _slices = const [];
  List<_BarberRank> _barberMonth = const [];
  DateTime? _dashboardMonth;

  @override
  void initState() {
    super.initState();
    _loadMonthDistribution();
  }

  String _dateOnly(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final barbersRows = await supabase.from('barbers').select('id');
      final servicesRows = await supabase.from('services').select('id');
      final appointmentsRows = await supabase.from('appointments').select('id');

      final b = (barbersRows as List).length;
      final s = (servicesRows as List).length;
      final a = (appointmentsRows as List).length;

      final slices = <_Slice>[
        _Slice(
          value: b.toDouble(),
          color: const Color(0xFF1E88E5),
          label: 'Barbeiros',
        ),
        _Slice(
          value: s.toDouble(),
          color: const Color(0xFFFFC107),
          label: 'Serviços',
        ),
        _Slice(
          value: a.toDouble(),
          color: const Color(0xFFD81B60),
          label: 'Agendamentos',
        ),
      ];

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);
      final monthRows = await supabase
          .from('appointments')
          .select('barber_id, barbers:barber_id(name)')
          .gte('appointment_date', _dateOnly(start))
          .lt('appointment_date', _dateOnly(end));
      final list = List<Map<String, dynamic>>.from(monthRows);
      final map = <String, _BarberRank>{};
      for (final r in list) {
        final id = (r['barber_id'] ?? '').toString();
        final name = (r['barbers'] is Map)
            ? ((r['barbers']['name'] ?? '').toString())
            : '';
        final current = map[id];
        if (current == null) {
          map[id] = _BarberRank(
            id: id,
            name: name.isEmpty ? 'Sem nome' : name,
            count: 1,
          );
        } else {
          map[id] = _BarberRank(
            id: id,
            name: current.name,
            count: current.count + 1,
          );
        }
      }
      final ranks = map.values.toList()
        ..sort((a, b) => b.count.compareTo(a.count));

      setState(() {
        _barbers = b;
        _services = s;
        _appointments = a;
        _slices = slices;
        _barberMonth = ranks;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMonthDistribution() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      var month = DateTime(DateTime.now().year, DateTime.now().month, 1);
      var list = await _loadAppointmentsForMonth(supabase, month);

      if (list.isEmpty) {
        final latestRows = await supabase
            .from('appointments')
            .select('appointment_date')
            .order('appointment_date', ascending: false)
            .limit(1);
        final latestList = List<Map<String, dynamic>>.from(latestRows);
        if (latestList.isNotEmpty) {
          final latestDate = DateTime.tryParse(
            latestList.first['appointment_date']?.toString() ?? '',
          );
          if (latestDate != null) {
            month = DateTime(latestDate.year, latestDate.month, 1);
            list = await _loadAppointmentsForMonth(supabase, month);
          }
        }
      }
      final totals = <String, double>{};
      final counts = <String, int>{};
      final names = <String, String>{};
      for (final r in list) {
        final id = (r['barber_id'] ?? '').toString();
        String name = '';
        final barberRaw = r['barbers'];
        if (barberRaw is Map) {
          name = barberRaw['name']?.toString() ?? '';
        } else if (barberRaw is List && barberRaw.isNotEmpty) {
          final first = barberRaw.first;
          if (first is Map) name = first['name']?.toString() ?? '';
        }
        names[id] = (name.isEmpty ? 'Sem nome' : name);

        double price = 0.0;
        final servicesRaw = r['services'];
        if (servicesRaw is Map) {
          final p = servicesRaw['price'] as num?;
          price = (p == null) ? 0.0 : p.toDouble();
        } else if (servicesRaw is List) {
          for (final s in servicesRaw) {
            if (s is Map) {
              final p = s['price'] as num?;
              if (p != null) price += p.toDouble();
            }
          }
        }

        totals[id] = (totals[id] ?? 0.0) + price;
        counts[id] = (counts[id] ?? 0) + 1;
      }

      final palette = <Color>[
        const Color(0xFF1E88E5),
        const Color(0xFFFFC107),
        const Color(0xFFD81B60),
        const Color(0xFF43A047),
        const Color(0xFF8E24AA),
        const Color(0xFFFF7043),
      ];

      final slices = <_Slice>[];
      var i = 0;
      totals.forEach((id, total) {
        final color = palette[i % palette.length];
        i++;
        slices.add(
          _Slice(value: total, color: color, label: names[id] ?? 'Barbeiro'),
        );
      });

      final ranks = counts.entries.map((e) {
        return _BarberRank(
          id: e.key,
          name: names[e.key] ?? 'Sem nome',
          count: e.value,
        );
      }).toList()..sort((a, b) => b.count.compareTo(a.count));

      setState(() {
        _dashboardMonth = month;
        _slices = slices;
        _barberMonth = ranks;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadAppointmentsForMonth(
    SupabaseClient supabase,
    DateTime month,
  ) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    var query = supabase
        .from('appointments')
        .select(
          'barber_id, barbers:barber_id(name), services:service_id(price)',
        )
        .gte('appointment_date', _dateOnly(start))
        .lt('appointment_date', _dateOnly(end));
    if (AdminSession.isBarber) {
      query = query.eq('barber_id', AdminSession.barberId!);
    }
    final rows = await query;
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Erro: $_error'))
          : RefreshIndicator(
              onRefresh: _loadMonthDistribution,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
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
                        Text(
                          'Top barbeiros do mês',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_dashboardMonth != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            DateFormat.yMMMM('pt_BR').format(_dashboardMonth!),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 12),
                        ..._buildBarberMonth(theme),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
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
                        Text(
                          'Resumo em pizza',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 220,
                          child: _slices.isEmpty
                              ? Center(
                                  child: Text(
                                    'Sem dados para exibir',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                )
                              : _PieChart(slices: _slices),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _slices.map((s) {
                            final total = _slices.fold<double>(
                              0,
                              (p, e) => p + e.value,
                            );
                            final pct = total == 0
                                ? 0
                                : ((s.value / total) * 100).round();
                            return Chip(
                              backgroundColor: theme.colorScheme.surfaceVariant,
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: s.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${s.label} • $pct%'),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }
}

class _Slice {
  final double value;
  final Color color;
  final String label;
  const _Slice({required this.value, required this.color, required this.label});
}

class _BarberRank {
  final String id;
  final String name;
  final int count;
  const _BarberRank({
    required this.id,
    required this.name,
    required this.count,
  });
}

extension on _DashboardScreenState {
  List<Widget> _buildBarberMonth(ThemeData theme) {
    if (_barberMonth.isEmpty) {
      return [Text('Sem dados no mês', style: theme.textTheme.bodyMedium)];
    }
    final maxCount = _barberMonth
        .map((e) => e.count)
        .fold<int>(0, (p, e) => e > p ? e : p);
    return _barberMonth.map((r) {
      final pct = maxCount == 0 ? 0.0 : r.count / maxCount;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.person),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${r.count}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth * pct;
                return Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Container(
                      width: w,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E88E5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    }).toList();
  }
}

class _PieChart extends StatelessWidget {
  final List<_Slice> slices;
  const _PieChart({required this.slices});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiePainter(slices: slices),
      child: const SizedBox.expand(),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<_Slice> slices;
  _PiePainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final double total = slices.fold<double>(0.0, (p, e) => p + e.value);
    final center = Offset(size.width / 2, size.height / 2);
    final double radius =
        math.min(size.width, size.height).toDouble() / 2.0 - 8.0;
    var start = -math.pi / 2.0;

    for (final s in slices) {
      final double sweep = total == 0.0
          ? 0.0
          : (s.value / total) * 2.0 * math.pi;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        paint,
      );
      start += sweep;
    }

    final holePaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.55, holePaint);
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
