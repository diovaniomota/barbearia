import 'package:intl/intl.dart';

class Service {
  final String id;
  final String name;
  final String description;
  final double price;
  final int durationMinutes;
  final int durationBlocks;
  final String imageUrl;

  /// Ordem manual definida no admin (arrastar p/ reordenar). Menor = primeiro.
  final int sortOrder;

  Service({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationMinutes,
    required this.imageUrl,
    this.durationBlocks = 1,
    this.sortOrder = 0,
  });

  String get formattedPrice =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(price);
  String get duration => '$durationMinutes min';

  /// Ex: 1 bloco → "30 min", 2 blocos → "1h", 3 blocos → "1h30".
  String get durationLabel {
    final mins = durationBlocks * 30;
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

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

  static String parseImageUrl(Map<String, dynamic> map) {
    final raw =
        map['image_url'] ??
        map['imageUrl'] ??
        map['photo_url'] ??
        map['photoUrl'] ??
        map['foto_url'] ??
        map['foto'] ??
        map['image'] ??
        map['cover'] ??
        '';
    final value = raw.toString().trim();
    return value == 'null' ? '' : value;
  }

  /// Converte do Supabase tolerando nomes diferentes no schema
  factory Service.fromMap(Map<String, dynamic> map) {
    final blocks = parseInt(map['duration_blocks']);
    return Service(
      id: map['id'].toString(),
      name: (map['name'] ?? map['titulo'] ?? 'Sem nome').toString(),
      description:
          (map['description'] ??
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
      durationBlocks: blocks < 1 ? 1 : blocks,
      imageUrl: parseImageUrl(map),
      sortOrder: parseInt(map['sort_order'] ?? map['sortOrder']),
    );
  }

  /// Ordena uma lista de serviços pela ordem manual e, em empate, pelo nome.
  static void sortByOrder(List<Service> list) {
    list.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0
          ? c
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
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
