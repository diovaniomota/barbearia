class Service {
  final String id;
  final String name;
  final String description;
  final double price;
  final int durationMinutes;
  final String imageUrl;

  Service({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationMinutes,
    required this.imageUrl,
  });

  String get formattedPrice => 'R\$ ${price.toStringAsFixed(2)}';
  String get duration => '${durationMinutes}min';

  // Helpers sem underscore (evita lint chato)
  static double parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  static int parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  /// Converte do Supabase tolerando nomes diferentes no schema
  factory Service.fromMap(Map<String, dynamic> map) {
    return Service(
      id: map['id'].toString(),
      name: (map['name'] ?? map['titulo'] ?? 'Sem nome').toString(),
      description: (map['description'] ??
              map['descricao'] ??
              map['details'] ??
              'Sem descrição')
          .toString(),
      price: parseDouble(map['price'] ?? map['valor'] ?? map['preco']),
      durationMinutes: parseInt(
        map['duration_minutes'] ??
            map['duration'] ??
            map['time_minutes'] ??
            map['duracao'],
      ),
      imageUrl:
          (map['image_url'] ?? map['image'] ?? map['cover'] ?? '').toString(),
    );
  }

  /// MOCK opcional – se telas antigas chamam getSampleServices()
  static List<Service> getSampleServices() {
    return [
      Service(
        id: '1',
        name: 'Corte Tradicional',
        description: 'Corte clássico masculino com tesoura e máquina',
        price: 25.0,
        durationMinutes: 30,
        imageUrl: 'https://picsum.photos/seed/corte/600/400',
      ),
      Service(
        id: '2',
        name: 'Barba Completa',
        description: 'Aparar e modelar barba com navalha e produtos especiais',
        price: 20.0,
        durationMinutes: 25,
        imageUrl: 'https://picsum.photos/seed/barba/600/400',
      ),
    ];
  }
}
