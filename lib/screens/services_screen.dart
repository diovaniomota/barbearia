import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/models/service.dart';
import 'package:barbearia/screens/book_appointment_screen.dart';
import 'package:barbearia/widgets/service_card.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  bool isLoading = true;
  String? errorMessage;
  List<Service> services = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from('services')
          .select('*')
          .order('name');

      final list = (rows as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        services = list.map(Service.fromMap).toList();
        isLoading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Erro Supabase: ${e.message}';
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Erro inesperado: $e';
        isLoading = false;
      });
    }
  }

  List<Service> get _filtered {
    if (_query.trim().isEmpty) return services;
    final q = _query.toLowerCase();
    return services.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadServices,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Nossos Serviços',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _SearchButton(onChanged: (t) => setState(() => _query = t)),
                ],
              ),
              const SizedBox(height: 16),
              ..._filtered.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 14.0),
                  child: ServiceCard(
                    service: s,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookAppointmentScreen(service: s),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchButton extends StatefulWidget {
  const _SearchButton({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  State<_SearchButton> createState() => _SearchButtonState();
}

class _SearchButtonState extends State<_SearchButton> {
  bool _open = false;
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_open) {
      return IconButton(
        tooltip: 'Buscar',
        onPressed: () => setState(() => _open = true),
        icon: Icon(Icons.search, color: theme.colorScheme.onSurface),
      );
    }
    return SizedBox(
      width: 220,
      child: TextField(
        controller: _controller,
        autofocus: true,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: 'Buscar...',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          suffixIcon: IconButton(
            onPressed: () {
              _controller.clear();
              widget.onChanged('');
              setState(() => _open = false);
            },
            icon: const Icon(Icons.close),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
