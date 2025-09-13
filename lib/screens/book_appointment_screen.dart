import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/models/service.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class BarberLite {
  final String id;
  final String name;
  final String avatarUrl;
  final double rating;

  BarberLite({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.rating,
  });

  factory BarberLite.fromMap(Map<String, dynamic> map) {
    final rawRating = map['rating'] ?? map['score'] ?? map['stars'];
    final doubleRating = rawRating is num
        ? rawRating.toDouble()
        : double.tryParse('${rawRating ?? ''}') ?? 0.0;

    final avatar =
        (map['avatar_url'] ??
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

  bool _loadingBarbers = true;
  String? _barbersError;
  List<BarberLite> _barbers = const [];

  @override
  void initState() {
    super.initState();
    _selectedService = widget.service;
    if (_selectedService != null) _currentStep = 1;
    _loadBarbers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadBarbers() async {
    setState(() {
      _loadingBarbers = true;
      _barbersError = null;
    });

    try {
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

  Future<void> _saveAppointment() async {
    if (_selectedService == null ||
        _selectedBarberId == null ||
        _selectedDateTime == null ||
        _nameController.text.isEmpty ||
        _phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos antes de salvar.'),
        ),
      );
      return;
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      final response = await Supabase.instance.client
          .from('appointments')
          .insert({
            'service_id': _selectedService!.id,
            'barber_id': _selectedBarberId,
            'scheduled_at': _selectedDateTime!.toUtc().toIso8601String(),
            'customer_name': _nameController.text.trim(),
            'customer_phone': _phoneController.text.trim(),
            if (userId != null) 'user_id': userId,
          })
          .select()
          .single();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agendamento confirmado!')));

      Navigator.pop(context, response);
    } on PostgrestException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro Supabase: ${e.message}')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro inesperado: $e')));
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
            _saveAppointment();
          }
        },
        steps: [
          Step(
            isActive: _currentStep >= 0,
            title: const Text('Escolha o Serviço'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedService == null)
                  _SelectServiceFromSupabase(
                    onSelect: (s) {
                      setState(() {
                        _selectedService = s;
                        _currentStep = 1;
                      });
                    },
                  )
                else
                  _ServiceHeader(service: _selectedService!),
              ],
            ),
          ),
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
                  ..._barbers.map(
                    (b) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _barberTile(
                        id: b.id,
                        name: b.name,
                        avatarUrl: b.avatarUrl,
                        rating: b.rating,
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    MaskTextInputFormatter(
                      mask: '(##) #####-####',
                      filter: {'#': RegExp(r'[0-9]')},
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    hintText: '(00) 00000-0000',
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
              ? theme.colorScheme.primaryContainer.withAlpha(64)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withAlpha(51),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.primary,
              foregroundImage: (avatarUrl.isNotEmpty)
                  ? NetworkImage(avatarUrl)
                  : null,
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
                      Icon(
                        Icons.star,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: theme.textTheme.bodySmall,
                      ),
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
        border: Border.all(color: theme.colorScheme.outline.withAlpha(51)),
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
                Text(
                  '${service.formattedPrice} • ${service.duration}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectServiceFromSupabase extends StatefulWidget {
  const _SelectServiceFromSupabase({required this.onSelect});
  final void Function(Service) onSelect;

  @override
  State<_SelectServiceFromSupabase> createState() =>
      __SelectServiceFromSupabaseState();
}

class __SelectServiceFromSupabaseState
    extends State<_SelectServiceFromSupabase> {
  late final Future<List<Service>> _servicesFuture;

  @override
  void initState() {
    super.initState();
    _servicesFuture = _fetchServices();
  }

  Future<List<Service>> _fetchServices() async {
    final response = await Supabase.instance.client
        .from('services')
        .select()
        .order('name');
    return (response as List)
        .map((serviceData) => Service.fromMap(serviceData))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Service>>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        final services = snapshot.data ?? [];
        if (services.isEmpty) {
          return const Center(child: Text('Nenhum serviço encontrado.'));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Selecione um serviço abaixo:'),
            const SizedBox(height: 8),
            ...services.map(
              (s) => ListTile(
                leading: const Icon(Icons.content_cut),
                title: Text(s.name),
                subtitle: Text('${s.formattedPrice} • ${s.duration}'),
                onTap: () => widget.onSelect(s),
              ),
            ),
          ],
        );
      },
    );
  }
}
