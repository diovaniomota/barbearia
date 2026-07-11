import 'package:supabase_flutter/supabase_flutter.dart';

class AgendaRepository {
  AgendaRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>?> fetchAvailability({
    required String barberId,
    required int dayOfWeek,
  }) async {
    final rows = await _client
        .from('barber_availability')
        .select('start_time,end_time,is_available,break_start,break_end')
        .eq('barber_id', barberId)
        .eq('day_of_week', dayOfWeek)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows as List);
    if (list.isNotEmpty) return list.first;
    return null;
  }

  Future<List<String>> fetchExtraSlotTimes({
    required String barberId,
    required String dateYmd,
  }) async {
    final rows = await _client
        .from('extra_slots')
        .select('slot_time')
        .eq('barber_id', barberId)
        .eq('slot_date', dateYmd);
    return [
      for (final r in (rows as List))
        _hhmm('${(r as Map)['slot_time']}'),
    ];
  }

  Future<List<Map<String, dynamic>>> fetchBlockedSlots({
    required String barberId,
    required String dateYmd,
  }) async {
    final rows = await _client
        .from('blocked_slots')
        .select('id,time')
        .eq('barber_id', barberId)
        .eq('date', dateYmd);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<String?> fetchDayBlockId({
    required String barberId,
    required String dateYmd,
  }) async {
    try {
      final dayBlocks = await _client
          .from('barber_blocked_days')
          .select('id')
          .eq('barber_id', barberId)
          .lte('date_from', dateYmd)
          .gte('date_to', dateYmd)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(dayBlocks as List);
      if (list.isNotEmpty) {
        return list.first['id']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> blockSlot({
    required String barberId,
    required String dateYmd,
    required String timeHms,
  }) async {
    await _client.from('blocked_slots').insert({
      'barber_id': barberId,
      'date': dateYmd,
      'time': timeHms,
    });
  }

  Future<void> unblockSlot({
    String? blockedId,
    String? barberId,
    String? dateYmd,
    String? timeHms,
  }) async {
    final q = _client.from('blocked_slots').delete();
    if (blockedId != null) {
      await q.eq('id', blockedId);
    } else {
      await q
          .eq('barber_id', barberId!)
          .eq('date', dateYmd!)
          .eq('time', timeHms!);
    }
  }

  Future<void> addExtraSlot({
    required String barberId,
    required String dateYmd,
    required String timeHms,
  }) async {
    await _client.from('extra_slots').insert({
      'barber_id': barberId,
      'slot_date': dateYmd,
      'slot_time': timeHms,
    });
  }

  String _hhmm(String raw) {
    final p = raw.split(':');
    if (p.length < 2) return raw;
    return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
  }
}
