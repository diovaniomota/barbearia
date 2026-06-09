import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barbearia/models/service.dart';
import 'package:barbearia/screens/book_appointment_screen.dart';

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
      final list = (response as List).map((e) => Service.fromMap(e)).toList();
      Service.sortByOrder(list);
      return list;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('oauth_client_id')) {
        await Supabase.instance.client.auth.signOut();
        final response = await Supabase.instance.client
            .from('services')
            .select()
            .order('name');
        final list = (response as List).map((e) => Service.fromMap(e)).toList();
        Service.sortByOrder(list);
        return list;
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
      backgroundColor: _P.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _P.gold,
          backgroundColor: _P.card,
          onRefresh: _refresh,
          child: FutureBuilder<List<Service>>(
            future: _servicesFuture,
            builder: (context, snapshot) {
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              final services = snapshot.data ?? const <Service>[];

              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _PageHeader(count: services.length),
                  ),
                  if (loading)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate.fixed(const [
                          _Skeleton(),
                          SizedBox(height: 12),
                          _Skeleton(),
                          SizedBox(height: 12),
                          _Skeleton(),
                        ]),
                      ),
                    )
                  else if (snapshot.hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        icon: Icons.wifi_off_rounded,
                        title: 'Sem conexão',
                        subtitle: 'Puxe para baixo e tente novamente.',
                      ),
                    )
                  else if (services.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        icon: Icons.content_cut_rounded,
                        title: 'Nenhum serviço',
                        subtitle: 'Os serviços vão aparecer aqui.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
                      sliver: SliverList.separated(
                        itemCount: services.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _ServicePhotoCard(
                          service: services[i],
                          onTap: () => _openBooking(services[i]),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.count});

  final int count;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Logo centralizado ────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: SizedBox(
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Logo
                Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                  errorBuilder: (_, __, ___) => Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _P.gold, width: 2),
                    ),
                    child: const Icon(
                      Icons.content_cut_rounded,
                      color: _P.gold,
                      size: 48,
                    ),
                  ),
                ),
                // Badge de serviços no canto direito
                Positioned(right: 0, top: 0, child: _CountBadge(count: count)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Saudação ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(
                  color: _P.gold,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                '$_greeting!  ',
                style: tt.labelMedium?.copyWith(
                  color: _P.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'O que vai ser hoje?',
                style: tt.titleMedium?.copyWith(
                  color: _P.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Divisor SERVIÇOS ─────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(child: Divider(color: _P.border, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'SERVIÇOS',
                  style: tt.labelSmall?.copyWith(
                    color: _P.muted,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: _P.border, thickness: 1)),
            ],
          ),
        ),

        const SizedBox(height: 8),

        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Count badge ───────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _P.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 17,
            height: 17,
            decoration: const BoxDecoration(
              color: _P.gold,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFF0C0D10),
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            count == 1 ? 'serviço' : 'serviços',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: _P.muted),
          ),
        ],
      ),
    );
  }
}

// ── Photo card ────────────────────────────────────────────────────────────────

class _ServicePhotoCard extends StatelessWidget {
  const _ServicePhotoCard({required this.service, required this.onTap});

  final Service service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = service.imageUrl.trim();
    final desc = service.description.trim();
    final hasDesc = desc.isNotEmpty && !desc.toLowerCase().contains('sem');

    return SizedBox(
      height: 150,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: _P.card,
                border: Border.all(color: _P.gold, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ServiceImage(url: url),

                  // Gradient overlay — strong at bottom for readability
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.10),
                          Colors.black.withValues(alpha: 0.88),
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),

                  // Text content pinned to bottom-left
                  Positioned(
                    left: 16,
                    right: 56,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          service.name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                shadows: const [
                                  Shadow(color: Colors.black54, blurRadius: 8),
                                ],
                              ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              service.formattedPrice,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: _P.gold,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              '  ·  ',
                              style: TextStyle(color: _P.muted, fontSize: 12),
                            ),
                            Text(
                              service.durationLabel,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: _P.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                        if (hasDesc) ...[
                          const SizedBox(height: 3),
                          Text(
                            desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Arrow icon pinned to bottom-right
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _P.gold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _P.gold.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: _P.gold,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tap overlay
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceImage extends StatelessWidget {
  const _ServiceImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _Placeholder();

    return Image.network(
      url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _Placeholder();
      },
      errorBuilder: (_, _, _) => const _Placeholder(),
    );
  }
}

// ── Placeholder (no image) ────────────────────────────────────────────────────

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1C22), Color(0xFF0E1014)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.content_cut_rounded,
          color: Color(0xFF2A2E3A),
          size: 52,
        ),
      ),
    );
  }
}

// ── Skeleton ──────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: _P.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _P.border),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _P.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _P.border),
              ),
              child: Icon(icon, color: _P.gold, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _P.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _P.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Palette ───────────────────────────────────────────────────────────────────

class _P {
  static const Color bg = Color(0xFF080808);
  static const Color card = Color(0xFF111111);
  static const Color border = Color(0xFF222222);
  static const Color gold = Color(0xFFF5C200);
  static const Color text = Color(0xFFF0EDE8);
  static const Color muted = Color(0xFF6B7280);
}
