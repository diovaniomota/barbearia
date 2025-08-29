import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/models/service.dart';

/// Modelo leve para a listagem de barbeiros vindos do Supabase.
class BarberLite {
  final String id;
  final String name;
  final String avatarUrl; // pode vir vazio
  final double rating; // opcional

  BarberLite({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.rating,
  });

  /// Aceita vários nomes de coluna para evitar "column does not exist".
  factory BarberLite.fromMap(Map<String, dynamic> map) {
    // rating pode ser null / num / string ou ter outro nome
    final rawRating = map['rating'] ?? map['score'] ?? map['stars'];
    final doubleRating = rawRating is num
        ? rawRating.toDouble()
        : double.tryParse('${rawRating ?? ''}') ?? 0.0;

    // tenta vários nomes possíveis para a foto
    final avatar = (map['avatar_url'] ??
            map['avatar'] ??
            map['photo_url'] ??
            map['image_url'] ??
            '')
        .toString();

    return BarberLite(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      avatarUrl: avatar,
      rating: doubleRating,
    );
  }
}

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key, this.service});

  /// Serviço pré‑selecionado (quando vier da lista de serviços). Pode ser null.
  final Service? service;

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  int _currentStep = 0;

  Service? _selectedService;
  String? _selectedBarberId;
  DateTime? _selectedDateTime;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Estado da lista de barbeiros (Supabase)
  bool _loadingBarbers = true;
  String? _barbersError;
  List<BarberLite> _barbers = const [];

  @override
  void initState() {
    super.initState();
    _selectedService = widget.service;
    if (_selectedService != null) _currentStep = 1; // pula a etapa do serviço
    _loadBarbers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Busca barbeiros do Supabase.
  Future<void> _loadBarbers() async {
    setState(() {
      _loadingBarbers = true;
      _barbersError = null;
    });

    try {
      // Seleciona tudo para não quebrar com nomes de coluna diferentes
      final data = await Supabase.instance.client
          .from('barbers')
          .select('*')
          .order('name');

      final list = (data as List).cast<Map<String, dynamic>>();
      final parsed = list.map(BarberLite.fromMap).toList();

      if (!mounted) return;
      setState(() {
        _barbers = parsed;
        _loadingBarbers = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _barbersError = 'Erro Supabase: ${e.message}';
        _loadingBarbers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _barbersError = 'Erro inesperado: $e';
        _loadingBarbers = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Agendar Horário')),
      body: Stepper(
        currentStep: _currentStep,
        onStepCancel: () {
          if (_currentStep > 0) setState(() => _currentStep--);
        },
        onStepContinue: () {
          if (_currentStep < 3) {
            setState(() => _currentStep++);
          } else {
            // TODO: salvar no Supabase (appointments)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Agendamento confirmado!')),
            );
            Navigator.pop(context);
          }
        },
        steps: [
          // 0) Serviço
          Step(
            isActive: _currentStep >= 0,
            title: const Text('Escolha o Serviço'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedService == null)
                  _SelectServicePlaceholder(onSelect: (s) {
                    setState(() {
                      _selectedService = s;
                      _currentStep = 1;
                    });
                  })
                else
                  _ServiceHeader(service: _selectedService!),
              ],
            ),
          ),

          // 1) Barbeiro (lista vinda do Supabase)
          Step(
            isActive: _currentStep >= 1,
            title: const Text('Escolha o Barbeiro'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadingBarbers)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_barbersError != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_barbersError!, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _loadBarbers,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  )
                else if (_barbers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Nenhum barbeiro encontrado.'),
                  )
                else
                  ..._barbers.map((b) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _barberTile(
                          id: b.id,
                          name: b.name,
                          avatarUrl: b.avatarUrl,
                          rating: b.rating,
                        ),
                      )),
              ],
            ),
          ),

          // 2) Data e horário
          Step(
            isActive: _currentStep >= 2,
            title: const Text('Data e Horário'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedDateTime == null
                      ? 'Nenhum horário selecionado'
                      : 'Selecionado: $_selectedDateTime',
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 60)),
                      initialDate: now,
                    );
                    if (date == null) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (time == null) return;
                    if (!mounted) return;
                    setState(() {
                      _selectedDateTime = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                  child: const Text('Selecionar data e horário'),
                ),
              ],
            ),
          ),

          // 3) Dados pessoais
          Step(
            isActive: _currentStep >= 3,
            title: const Text('Dados Pessoais'),
            content: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Card simples de barbeiro
  Widget _barberTile({
    required String id,
    required String name,
    required String avatarUrl,
    required double rating,
  }) {
    final theme = Theme.of(context);
    final selected = _selectedBarberId == id;

    return InkWell(
      onTap: () => setState(() => _selectedBarberId = id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.primary,
              foregroundImage:
                  (avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
              child: (avatarUrl.isEmpty)
                  ? Icon(Icons.person, color: theme.colorScheme.onPrimary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.star,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(rating.toStringAsFixed(1),
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader({required this.service});
  final Service service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.content_cut, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('${service.formattedPrice} • ${service.duration}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder simples: lista alguns serviços exemplo.
/// No app final, você pode abrir ServicesScreen e retornar o Service escolhido.
class _SelectServicePlaceholder extends StatelessWidget {
  const _SelectServicePlaceholder({required this.onSelect});
  final void Function(Service) onSelect;

  @override
  Widget build(BuildContext context) {
    final sample = Service.getSampleServices();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Selecione um serviço abaixo (exemplo):'),
        const SizedBox(height: 8),
        ...sample.map((s) => ListTile(
              leading: const Icon(Icons.content_cut),
              title: Text(s.name),
              subtitle: Text('${s.formattedPrice} • ${s.duration}'),
              onTap: () => onSelect(s),
            )),
      ],
    );
  }
}
