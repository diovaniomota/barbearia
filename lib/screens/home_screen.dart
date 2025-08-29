import 'package:barbearia/screens/book_appointment_screen.dart';
import 'package:barbearia/screens/services_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/models/barber.dart';
import 'package:barbearia/models/service.dart';
import 'package:barbearia/widgets/barber_card.dart';
import 'package:barbearia/widgets/service_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<List<Service>>? _popularServicesFuture;
  // NOVO: Future para buscar os barbeiros
  Future<List<Barber>>? _barbersFuture;

  @override
  void initState() {
    super.initState();
    // Carrega os dados iniciais de serviços e barbeiros
    _loadData();
  }

  /// Carrega todos os dados necessários para a tela.
  void _loadData() {
    _popularServicesFuture = _fetchPopularServices();
    _barbersFuture = _fetchBarbers();
  }

  /// Busca os serviços populares no Supabase.
  Future<List<Service>> _fetchPopularServices() async {
    final response = await Supabase.instance.client
        .from('services')
        .select()
        .order('name')
        .limit(3);
    return (response as List)
        .map((serviceData) => Service.fromMap(serviceData))
        .toList();
  }

  /// NOVO: Busca os barbeiros no Supabase.
  Future<List<Barber>> _fetchBarbers() async {
    final response = await Supabase.instance.client
        .from('barbers') // Busca na tabela 'barbers'
        .select()
        .order('name');
    // Usa o construtor Barber.fromMap que você já tem
    return (response as List)
        .map((barberData) => Barber.fromMap(barberData))
        .toList();
  }

  /// Função de atualização (agora atualiza serviços E barbeiros).
  Future<void> _handleRefresh() async {
    setState(() {
      _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (sem alterações)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bem-vindo!',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Agende seu horário na melhor barbearia',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(178),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.notifications_outlined,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Card de Agendamento (sem alterações)
                FutureBuilder<List<Service>>(
                  future: _popularServicesFuture,
                  builder: (context, snapshot) {
                    final popularServices = snapshot.data ?? [];
                    return Container(
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.primary.withAlpha(204),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookAppointmentScreen(
                                  service: popularServices.isNotEmpty
                                      ? popularServices.first
                                      : null,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Agendar Horário',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              color:
                                                  theme.colorScheme.onPrimary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Escolha seu barbeiro e horário',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme.colorScheme.onPrimary
                                                  .withAlpha(230),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onPrimary
                                        .withAlpha(51),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.calendar_month,
                                    size: 32,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Seção de Serviços Populares (sem alterações)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Serviços Populares',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ServicesScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'Ver todos',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 120,
                  child: FutureBuilder<List<Service>>(
                    future: _popularServicesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Erro: ${snapshot.error}'));
                      }
                      final popularServices = snapshot.data ?? [];
                      if (popularServices.isEmpty) {
                        return const Center(
                          child: Text('Nenhum serviço encontrado.'),
                        );
                      }
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: popularServices.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          return ServiceCard(
                            service: popularServices[index],
                            isCompact: true,
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),

                // Nossos Barbeiros (MODIFICADO)
                Text(
                  'Nossos Barbeiros',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                // FutureBuilder para exibir os barbeiros do Supabase
                FutureBuilder<List<Barber>>(
                  future: _barbersFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Erro ao buscar barbeiros: ${snapshot.error}',
                        ),
                      );
                    }
                    final barbers = snapshot.data ?? [];
                    if (barbers.isEmpty) {
                      return const Center(
                        child: Text('Nenhum barbeiro encontrado.'),
                      );
                    }
                    // Cria uma coluna com os cards dos barbeiros
                    return Column(
                      children: barbers
                          .map(
                            (barber) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: BarberCard(barber: barber),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
