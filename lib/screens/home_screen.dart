import 'package:barbearia/models/service.dart';
import 'package:barbearia/screens/book_appointment_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Service>> _servicesFuture;

  @override
  void initState() {
    super.initState();
    _servicesFuture = _fetchServices();
  }

  Future<List<Service>> _fetchServices() async {
    try {
      final response = await Supabase.instance.client
          .from('services')
          .select()
          .order('name');

      return (response as List)
          .map((serviceData) => Service.fromMap(serviceData))
          .toList();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('oauth_client_id')) {
        await Supabase.instance.client.auth.signOut();
        final response = await Supabase.instance.client
            .from('services')
            .select()
            .order('name');

        return (response as List)
            .map((serviceData) => Service.fromMap(serviceData))
            .toList();
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _servicesFuture = _fetchServices();
    });
    await _servicesFuture;
  }

  void _openBooking(Service service) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookAppointmentScreen(service: service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _HomePalette.frame,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: _HomePalette.background),
              child: RefreshIndicator(
                color: _HomePalette.gold,
                backgroundColor: _HomePalette.panel,
                onRefresh: _refresh,
                child: FutureBuilder<List<Service>>(
                  future: _servicesFuture,
                  builder: (context, snapshot) {
                    final isLoading =
                        snapshot.connectionState == ConnectionState.waiting;
                    final services = snapshot.data ?? const <Service>[];

                    return CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _CatalogHeader(serviceCount: services.length),
                        ),
                        if (isLoading)
                          const SliverPadding(
                            padding: EdgeInsets.fromLTRB(14, 8, 14, 96),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate.fixed([
                                _ServiceSkeleton(),
                                SizedBox(height: 12),
                                _ServiceSkeleton(),
                                SizedBox(height: 12),
                                _ServiceSkeleton(),
                              ]),
                            ),
                          )
                        else if (snapshot.hasError)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(
                              icon: Icons.wifi_off_rounded,
                              title: 'Servicos indisponiveis',
                              subtitle: 'Puxe para baixo para tentar de novo.',
                            ),
                          )
                        else if (services.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(
                              icon: Icons.content_cut_rounded,
                              title: 'Nenhum servico cadastrado',
                              subtitle: 'Os atendimentos vao aparecer aqui.',
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                            sliver: SliverList.separated(
                              itemCount: services.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final service = services[index];
                                return _ServiceTile(
                                  service: service,
                                  onTap: () => _openBooking(service),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({required this.serviceCount});

  final int serviceCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _LogoMark(),
              const SizedBox(width: 10),
              Text(
                'Agenda Servico',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _HomePalette.mint,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: () {},
                icon: const Icon(Icons.tune_rounded, color: _HomePalette.gold),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Escolha seu atendimento',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _HomePalette.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Selecione um servico para iniciar o agendamento.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _HomePalette.muted),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _HeaderChip(
                icon: Icons.content_cut_rounded,
                label: '$serviceCount servicos',
              ),
              const SizedBox(width: 8),
              const _HeaderChip(
                icon: Icons.schedule_rounded,
                label: 'Horario online',
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Catalogo',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: _HomePalette.gold,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HomePalette.gold,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.spa_rounded, color: _HomePalette.background),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HomePalette.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _HomePalette.stroke),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon, color: _HomePalette.gold, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _HomePalette.text,
                    fontWeight: FontWeight.w700,
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

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.onTap});

  final Service service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final description = service.description.trim();
    final showDescription =
        description.isNotEmpty && !description.toLowerCase().contains('sem');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _HomePalette.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _HomePalette.stroke),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _ServiceImage(imageUrl: service.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _HomePalette.text,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      if (showDescription) ...[
                        const SizedBox(height: 5),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _HomePalette.muted),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _MetaPill(label: service.formattedPrice),
                          const SizedBox(width: 7),
                          _MetaPill(label: service.duration),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: _HomePalette.gold,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceImage extends StatelessWidget {
  const _ServiceImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 82,
        height: 82,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: _HomePalette.panel),
          child: url.isEmpty
              ? const Icon(Icons.content_cut_rounded, color: _HomePalette.gold)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    return const Icon(
                      Icons.content_cut_rounded,
                      color: _HomePalette.gold,
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _HomePalette.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: _HomePalette.gold,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ServiceSkeleton extends StatelessWidget {
  const _ServiceSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 104,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HomePalette.card,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _HomePalette.gold, size: 36),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _HomePalette.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _HomePalette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePalette {
  static const Color frame = Color(0xFF223C3C);
  static const Color background = Color(0xFF0F0C0B);
  static const Color panel = Color(0xFF1C1714);
  static const Color card = Color(0xFF181110);
  static const Color stroke = Color(0xFF37241F);
  static const Color gold = Color(0xFFF6C84F);
  static const Color mint = Color(0xFF20D8B2);
  static const Color text = Color(0xFFFFF6EA);
  static const Color muted = Color(0xFFB9A394);
}
