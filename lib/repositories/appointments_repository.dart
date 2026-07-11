import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized appointment queries/mutations used by admin + booking.
class AppointmentsRepository {
  AppointmentsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> fetchDay({
    required String barberId,
    required String dateYmd,
  }) async {
    final rows = await _client
        .from('appointments')
        .select(
          'id,appointment_time,customer_name,customer_phone,status,source,'
          'total_price,created_by,services:service_id(name)',
        )
        .eq('barber_id', barberId)
        .eq('appointment_date', dateYmd);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Phones that already had a visit before [dateYmd].
  Future<Set<String>> returningPhones(
    Iterable<String> phones,
    String beforeDateYmd,
  ) async {
    final list = phones.where((p) => p.trim().isNotEmpty).toList();
    if (list.isEmpty) return {};
    final prior = await _client
        .from('appointments')
        .select('customer_phone')
        .inFilter('customer_phone', list)
        .lt('appointment_date', beforeDateYmd);
    final out = <String>{};
    for (final r in (prior as List)) {
      final ph = ((r as Map)['customer_phone'] ?? '').toString().trim();
      if (ph.isNotEmpty) out.add(ph);
    }
    return out;
  }

  Future<void> cancelAtSlot({
    required String barberId,
    required String dateYmd,
    required String timeHms,
  }) async {
    await _client
        .from('appointments')
        .update({'status': 'cancelled'})
        .eq('barber_id', barberId)
        .eq('appointment_date', dateYmd)
        .eq('appointment_time', timeHms);
  }

  Future<void> updatePrice(String appointmentId, double price) async {
    await _client
        .from('appointments')
        .update({'total_price': price})
        .eq('id', appointmentId);
  }

  Future<List<Map<String, dynamic>>> insertRows(
    List<Map<String, dynamic>> payload,
  ) async {
    final res = await _client.from('appointments').insert(payload).select();
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Realtime channel for day refresh callbacks.
  RealtimeChannel subscribeDayChanges({
    required String barberId,
    required String dateYmd,
    required void Function() onChange,
  }) {
    final channel = _client.channel('agenda-$barberId-$dateYmd');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blocked_slots',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'extra_slots',
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }
}
