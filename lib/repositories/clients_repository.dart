import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/utils/admin_session.dart';
import 'package:barbearia/utils/slot_logic.dart';

class ClientSummary {
  final String name;
  final String phone;
  final int visitCount;
  final DateTime? lastVisit;
  final DateTime? firstVisit;
  final bool isPlanClient;

  const ClientSummary({
    required this.name,
    required this.phone,
    required this.visitCount,
    this.lastVisit,
    this.firstVisit,
    this.isPlanClient = false,
  });
}

/// Aggregates appointments into a client CRM-style list (by phone).
class ClientsRepository {
  ClientsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ClientSummary>> fetchAll({String? search}) async {
    var query = _client
        .from('appointments')
        .select(
          'appointment_date, customer_name, customer_phone, is_plan_client, '
          'status, users:user_id(name, phone)',
        )
        .not('status', 'in', '("cancelled","canceled","no_show")');

    if (AdminSession.isBarber && AdminSession.barberId != null) {
      query = query.eq('barber_id', AdminSession.barberId!);
    }

    final rows = List<Map<String, dynamic>>.from(await query);

    final names = <String, String>{};
    final phones = <String, String>{};
    final visits = <String, int>{};
    final last = <String, DateTime>{};
    final first = <String, DateTime>{};
    final plan = <String, bool>{};

    for (final r in rows) {
      final usersRaw = r['users'];
      String userName = '';
      String userPhone = '';
      if (usersRaw is Map) {
        userName = usersRaw['name']?.toString() ?? '';
        userPhone = usersRaw['phone']?.toString() ?? '';
      }
      final cName = (r['customer_name']?.toString() ?? '').trim();
      final cPhone = (r['customer_phone']?.toString() ?? '').trim();
      final name = cName.isNotEmpty ? cName : userName;
      final rawPhone = cPhone.isNotEmpty ? cPhone : userPhone;
      final digits = SlotLogic.normalizePhone(rawPhone);
      if (digits.length < 10) continue;

      final dt = DateTime.tryParse(r['appointment_date']?.toString() ?? '');
      visits[digits] = (visits[digits] ?? 0) + 1;
      if (name.isNotEmpty) names[digits] = name;
      phones[digits] = rawPhone;
      if (r['is_plan_client'] == true) plan[digits] = true;

      if (dt != null) {
        final curLast = last[digits];
        if (curLast == null || dt.isAfter(curLast)) last[digits] = dt;
        final curFirst = first[digits];
        if (curFirst == null || dt.isBefore(curFirst)) first[digits] = dt;
      }
    }

    var list = visits.keys.map((digits) {
      return ClientSummary(
        name: names[digits] ?? 'Cliente',
        phone: phones[digits] ?? digits,
        visitCount: visits[digits] ?? 0,
        lastVisit: last[digits],
        firstVisit: first[digits],
        isPlanClient: plan[digits] == true,
      );
    }).toList();

    final q = (search ?? '').trim().toLowerCase();
    if (q.isNotEmpty) {
      final qDigits = SlotLogic.normalizePhone(q);
      list = list.where((c) {
        final n = c.name.toLowerCase();
        final p = SlotLogic.normalizePhone(c.phone);
        return n.contains(q) || p.contains(qDigits);
      }).toList();
    }

    list.sort((a, b) {
      final la = a.lastVisit ?? DateTime.fromMillisecondsSinceEpoch(0);
      final lb = b.lastVisit ?? DateTime.fromMillisecondsSinceEpoch(0);
      return lb.compareTo(la);
    });
    return list;
  }
}
