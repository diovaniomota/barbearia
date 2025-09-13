import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfile extends StatefulWidget {
  const EditProfile({super.key, required this.name, this.email, this.phone});

  final String name;
  final String? email;
  final String? phone;

  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;

  String? _avatarUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
    _emailCtrl = TextEditingController(text: widget.email ?? '');
    _phoneCtrl = TextEditingController(text: widget.phone ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first.substring(0, 1) : '';
    final last = parts.length > 1 ? parts.last.substring(0, 1) : '';
    final initials = (first + last).toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }

  Future<void> _onChangeAvatar() async {
    // Aqui você pode integrar image_picker/file_picker + upload para o Storage
    // Depois de subir, setState(() => _avatarUrl = 'URL do Storage');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seletor de imagem não implementado.')),
    );
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você precisa estar autenticado.')),
      );
      return;
    }

    final String name = _nameCtrl.text.trim();
    final String? phone = _phoneCtrl.text.trim().isEmpty
        ? null
        : _phoneCtrl.text.trim();
    final String? newEmail = _emailCtrl.text.trim().isEmpty
        ? null
        : _emailCtrl.text.trim();
    final String? currentEmail = user.email;

    setState(() => _saving = true);

    try {
      // 1) Atualizar tabela public.users (upsert com id = auth.uid())
      final payload = <String, dynamic>{
        'id': user.id, // importante pro onConflict
        'name': name,
        'email': newEmail, // manter sincronizado com tabela
        'phone': phone,
        'avatar_url': _avatarUrl, // pode ser null, tudo bem
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Usar upsert para garantir que o registro seja criado/atualizado
      await supabase.from('users').upsert(payload, onConflict: 'id');

      // 2) (Opcional) alterar e-mail no Auth caso tenha mudado
      if (newEmail != null && newEmail != currentEmail) {
        await supabase.auth.updateUser(UserAttributes(email: newEmail));
      }

      // 3) Aguardar um pouco para garantir que a transação foi commitada
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado com sucesso!')),
      );

      // Retorna os dados atualizados para a tela anterior
      Navigator.of(context).pop({
        'name': name,
        'email': newEmail,
        'phone': phone,
        'avatar_url': _avatarUrl,
        'success': true, // Indica sucesso explicitamente
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro Supabase: ${e.message}')));
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro Auth: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro inesperado: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _inputDecoration(
    String label, {
    String? hint,
    Widget? prefixIcon,
  }) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(14);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      filled: true,
      isDense: true,
      fillColor: theme.colorScheme.surface.withOpacity(0.9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: theme.colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final txt = theme.textTheme;
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Editar Perfil'), centerTitle: false),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card do Avatar + Nome
                  Card(
                    elevation: 0,
                    color: cs.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: cs.primaryContainer,
                                foregroundColor: cs.onPrimaryContainer,
                                backgroundImage: _avatarUrl != null
                                    ? NetworkImage(_avatarUrl!)
                                    : null,
                                child: _avatarUrl == null
                                    ? Text(
                                        _initialsFromName(
                                          _nameCtrl.text.isEmpty
                                              ? widget.name
                                              : _nameCtrl.text,
                                        ),
                                        style: txt.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      )
                                    : null,
                              ),
                              Positioned(
                                right: -6,
                                bottom: -2,
                                child: IconButton.filledTonal(
                                  style: IconButton.styleFrom(
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: const Size(28, 28),
                                  ),
                                  onPressed: _onChangeAvatar,
                                  icon: const Icon(Icons.edit, size: 18),
                                  tooltip: 'Trocar foto',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Informações pessoais',
                                  style: txt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Atualize seu nome, e-mail e contato.',
                                  style: txt.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Formulário
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: _inputDecoration(
                            'Nome completo',
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Informe seu nome';
                            }
                            if (v.trim().length < 3) {
                              return 'Nome muito curto';
                            }
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _inputDecoration(
                            'E-mail',
                            prefixIcon: const Icon(Icons.alternate_email),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return null; // opcional
                            final emailRe = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            );
                            if (!emailRe.hasMatch(v.trim())) {
                              return 'E-mail inválido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: _inputDecoration(
                            'Telefone',
                            prefixIcon: const Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          minLines: 3,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          decoration: _inputDecoration(
                            'Sobre você',
                            hint: 'Fale brevemente sobre você',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Ações
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: cs.outline),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(
                                  context,
                                ).pop(), // Não retorna nada (null)
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _saving ? null : _onSave,
                          child: _saving
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Salvar alterações'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Suas alterações serão aplicadas imediatamente.',
                      style: txt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
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
