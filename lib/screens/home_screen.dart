import 'dart:math' as math;

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
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: _HomePalette.background),
              child: RefreshIndicator(
                color: _HomePalette.gold,
                backgroundColor: _HomePalette.background,
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
                        const SliverToBoxAdapter(child: _HeroHeader()),
                        if (isLoading)
                          const SliverPadding(
                            padding: EdgeInsets.fromLTRB(8, 10, 8, 92),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate.fixed([
                                _ServiceSkeleton(),
                                SizedBox(height: 12),
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
                              title: 'Nao foi possivel carregar os servicos',
                              subtitle: 'Puxe para baixo e tente novamente.',
                            ),
                          )
                        else if (services.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(
                              icon: Icons.content_cut_rounded,
                              title: 'Nenhum servico cadastrado',
                              subtitle: 'Os servicos vao aparecer aqui.',
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(8, 10, 8, 92),
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

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0E1026),
              _HomePalette.background,
              _HomePalette.background,
            ],
            stops: [0.0, 0.34, 1.0],
          ),
        ),
        child: Stack(
          children: const [
            Positioned(left: 14, top: 14, child: _BrandWordmark()),
            Center(child: _SealLogo()),
          ],
        ),
      ),
    );
  }
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'AGENDA SERVICO',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: _HomePalette.mint,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _SealLogo extends StatelessWidget {
  const _SealLogo();

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
      color: _HomePalette.gold,
      fontWeight: FontWeight.w900,
    );

    return SizedBox(
      width: 132,
      height: 132,
      child: CustomPaint(
        painter: _SealPainter(),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('T', style: textStyle),
              const SizedBox(width: 8),
              const Icon(
                Icons.face_retouching_natural_rounded,
                color: _HomePalette.gold,
                size: 36,
              ),
              const SizedBox(width: 8),
              Text('D', style: textStyle),
            ],
          ),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = _HomePalette.gold;

    for (var i = 0; i < 40; i++) {
      final angle = i * 0.157;
      final start = Offset(
        center.dx + 58 * math.cos(angle),
        center.dy + 58 * math.sin(angle),
      );
      final end = Offset(
        center.dx + 63 * math.cos(angle + 0.07),
        center.dy + 63 * math.sin(angle + 0.07),
      );
      canvas.drawLine(start, end, paint);
    }

    canvas
      ..drawCircle(center, 56, paint)
      ..drawCircle(center, 43, paint..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    return SizedBox(
      height: showDescription ? 102 : 92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HomePalette.background,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _HomePalette.gold, width: 1.4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ServiceImage(imageUrl: service.imageUrl),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x99000000),
                          Color(0x55000000),
                          Color(0xD9000000),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          service.name.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _HomePalette.gold,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '${service.formattedPrice} - ${service.duration}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _HomePalette.gold,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        if (showDescription) ...[
                          const SizedBox(height: 2),
                          Text(
                            description.toUpperCase(),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: _HomePalette.gold,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
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
    if (url.isEmpty) return const ColoredBox(color: _HomePalette.background);

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) {
        return const ColoredBox(color: _HomePalette.background);
      },
    );
  }
}

class _ServiceSkeleton extends StatelessWidget {
  const _ServiceSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HomePalette.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _HomePalette.gold, width: 1.2),
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
                color: _HomePalette.gold,
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
  static const Color background = Color(0xFF0D0B0B);
  static const Color surface = Color(0xFF171111);
  static const Color gold = Color(0xFFFFD400);
  static const Color mint = Color(0xFF00C7A0);
  static const Color muted = Color(0xFFC8B1A1);
}
