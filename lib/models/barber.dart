class Barber {
  final String id;
  final String name;
  final String imageUrl;
  final List<String> specialties;
  final List<String> availableDays;
  final String workingHours;
  final double rating;

  Barber({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.specialties,
    required this.availableDays,
    required this.workingHours,
    this.rating = 0.0,
  });

  // --------- DB ---------
  factory Barber.fromMap(Map<String, dynamic> map) {
    List<String> _toStrList(dynamic v) {
      if (v == null) return const [];
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String) return v.split(',').map((s) => s.trim()).toList();
      return const [];
    }

    return Barber(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      imageUrl: (map['image_url'] ?? map['imageUrl'] ?? '').toString(),
      specialties: _toStrList(map['specialties']),
      availableDays: _toStrList(map['available_days'] ?? map['availableDays']),
      workingHours:
          (map['working_hours'] ?? map['workingHours'] ?? '').toString(),
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // Se quiser buscar do Supabase depois:
  // static Future<List<Barber>> fetchAll() async {
  //   final supabase = Supabase.instance.client;
  //   final rows = await supabase.from('barbers')
  //       .select<List<Map<String,dynamic>>>('*')
  //       .order('name');
  //   return rows.map(Barber.fromMap).toList();
  // }

  // --------- MOCK (compat com telas antigas) ---------
  static List<Barber> getSampleBarbers() {
    return [
      Barber(
        id: 'b1',
        name: 'Carlos',
        imageUrl: 'https://picsum.photos/seed/b1/200',
        specialties: const ['Corte', 'Degradê'],
        availableDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        workingHours: '09:00–18:00',
        rating: 4.8,
      ),
      Barber(
        id: 'b2',
        name: 'Mateus',
        imageUrl: 'https://picsum.photos/seed/b2/200',
        specialties: const ['Barba', 'Navalhado'],
        availableDays: const ['Tue', 'Wed', 'Thu', 'Sat'],
        workingHours: '10:00–19:00',
        rating: 4.6,
      ),
    ];
  }
}
