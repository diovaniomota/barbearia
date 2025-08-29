import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/models/barber.dart';
import 'package:barbearia/models/service.dart';

enum AppointmentStatus { pending, confirmed, completed, cancelled }

class Appointment {
  final String id;
  final String clientName;
  final String clientPhone;
  final Barber barber;
  final Service service;
  final DateTime dateTime;
  final AppointmentStatus status;
  final String? notes;

  Appointment({
    required this.id,
    required this.clientName,
    required this.clientPhone,
    required this.barber,
    required this.service,
    required this.dateTime,
    required this.status,
    this.notes,
  });

  String get statusText {
    switch (status) {
      case AppointmentStatus.pending:
        return 'Pendente';
      case AppointmentStatus.confirmed:
        return 'Confirmado';
      case AppointmentStatus.completed:
        return 'Concluído';
      case AppointmentStatus.cancelled:
        return 'Cancelado';
    }
  }

  // ---------- FETCH DO SUPABASE ----------
  static Future<List<Appointment>> fetchAppointmentsForCurrentUser() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado');
    }

    final List<dynamic> rows = await supabase
        .from('appointments')
        .select(
          '''
          id,
          client_name,
          client_phone,
          date_time,
          status,
          notes,
          barber:barbers(*),
          service:services(*)
          ''',
        )
        .eq('user_id', user.id) // troque para customer_id se for o seu schema
        .order('date_time', ascending: true);

    return rows
        .map((row) => Appointment.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  // ---------- MAP ----------
  factory Appointment.fromMap(Map<String, dynamic> map) {
    final barberMap = map['barber'] as Map<String, dynamic>?;
    final serviceMap = map['service'] as Map<String, dynamic>?;

    return Appointment(
      id: map['id'].toString(),
      clientName: (map['client_name'] ?? '').toString(),
      clientPhone: (map['client_phone'] ?? '').toString(),
      barber: barberMap != null ? Barber.fromMap(barberMap) : _fallbackBarber(),
      service:
          serviceMap != null ? Service.fromMap(serviceMap) : _fallbackService(),
      dateTime: DateTime.parse(map['date_time'].toString()),
      status: _parseStatus((map['status'] ?? 'pending').toString()),
      notes: map['notes'] as String?,
    );
  }

  static AppointmentStatus _parseStatus(String s) {
    switch (s.toLowerCase()) {
      case 'pending':
        return AppointmentStatus.pending;
      case 'confirmed':
        return AppointmentStatus.confirmed;
      case 'completed':
        return AppointmentStatus.completed;
      case 'cancelled':
      case 'canceled':
        return AppointmentStatus.cancelled;
      default:
        return AppointmentStatus.pending;
    }
  }

  // ---------- FALLBACKS compatíveis com seu construtor ----------
  static Barber _fallbackBarber() => Barber(
        id: 'unknown',
        name: 'Barbeiro',
        imageUrl: '',
        specialties: const [],
        availableDays: const [],
        workingHours: '',
        rating: 0,
      );

  static Service _fallbackService() => Service(
        id: 'unknown',
        name: 'Serviço',
        description: '',
        price: 0,
        durationMinutes: 0,
        imageUrl: '',
      );
}
