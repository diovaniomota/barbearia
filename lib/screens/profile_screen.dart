import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? userData;
  String? errorMessage;
  bool isLoading = true;

  int totalAppointments = 0;
  double? avgRating; // média de avaliações (reviews)

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final supabase = Supabase.instance.client;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          errorMessage = 'Usuário não autenticado.';
          isLoading = false;
        });
        return;
      }

      // 1) Perfil do usuário (public.users)
      final profile = await supabase
          .from('users')
          .select('name, email, phone, avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      // Ajuste a coluna de vínculo (user_id / customer_id) conforme seu schema
      final apptRes = await supabase
          .from('appointments')
          .select('id')
          .eq(
            'user_id',
            user.id,
          ); // <- mude para 'customer_id' se for o seu caso
      final apptCount = (apptRes as List).length;

      // 3) Média de avaliações (reviews)
      // Ajuste a coluna de vínculo e o nome do campo de nota (rating) se for diferente
      final reviews = await supabase
          .from('reviews')
          .select('rating')
          .eq('user_id', user.id); // ou .eq('customer_id', user.id)
      double? rating;
      if (reviews != null && reviews is List && reviews.isNotEmpty) {
        final nums = reviews
            .map((e) => (e['rating'] as num?)?.toDouble())
            .where((e) => e != null)
            .cast<double>()
            .toList();
        if (nums.isNotEmpty) {
          rating = nums.reduce((a, b) => a + b) / nums.length;
        }
      }

      setState(() {
        userData =
            profile ??
            {
              'name':
                  user.userMetadata?['name'] ??
                  user.email?.split('@').first ??
                  'Sem nome',
              'email': user.email ?? 'Sem email',
              'phone': user.userMetadata?['phone'] ?? 'Sem telefone',
              'avatar_url': user.userMetadata?['avatar_url'],
            };
        totalAppointments = apptCount;
        avgRating = rating; // pode ser null
        isLoading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        errorMessage = 'Erro Supabase: ${e.message}';
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Erro inesperado: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      );
    }

    final data = userData ?? {};
    final avatarUrl = data['avatar_url'] as String?;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Header
              Text(
                'Perfil',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 32),

              // Profile Picture and Info (mantendo seu layout antigo)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: theme.colorScheme.primary,
                      backgroundImage: avatarUrl != null
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null
                          ? Icon(
                              Icons.person,
                              size: 50,
                              color: theme.colorScheme.onPrimary,
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      (data['name'] ?? 'Sem nome').toString(),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (data['phone'] ?? 'Sem telefone').toString(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (data['email'] ?? 'Sem email').toString(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Menu Options (iguais aos anteriores)
              _buildMenuOption(
                context,
                icon: Icons.edit_outlined,
                title: 'Editar Perfil',
                onTap: () {
                  // TODO: navegue para tela de edição
                },
              ),
              _buildMenuOption(
                context,
                icon: Icons.history,
                title: 'Histórico de Agendamentos',
                onTap: () {
                  // TODO: navegue para histórico
                },
              ),
              _buildMenuOption(
                context,
                icon: Icons.favorite_outline,
                title: 'Serviços Favoritos',
                onTap: () {
                  // TODO
                },
              ),
              _buildMenuOption(
                context,
                icon: Icons.notifications_outlined,
                title: 'Notificações',
                onTap: () {
                  // TODO
                },
              ),
              _buildMenuOption(
                context,
                icon: Icons.help_outline,
                title: 'Ajuda e Suporte',
                onTap: () {
                  // TODO
                },
              ),
              _buildMenuOption(
                context,
                icon: Icons.info_outline,
                title: 'Sobre o App',
                onTap: () {
                  // TODO
                },
              ),
              const SizedBox(height: 32),

              // Stats Cards (dinâmicos agora)
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context,
                      icon: Icons.schedule,
                      value: totalAppointments.toString(),
                      label: 'Agendamentos',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      context,
                      icon: Icons.star,
                      value: (avgRating?.toStringAsFixed(1) ?? '—'),
                      label: 'Avaliação',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ====== helpers de UI (mesmos que você usava) ======
  Widget _buildMenuOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 20),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.1),
            theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
