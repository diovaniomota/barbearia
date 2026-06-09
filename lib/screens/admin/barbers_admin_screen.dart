import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:barbearia/supabase/supabase_config.dart';

class BarbersAdminScreen extends StatefulWidget {
  const BarbersAdminScreen({super.key});

  @override
  State<BarbersAdminScreen> createState() => _BarbersAdminScreenState();
}

class _BarbersAdminScreenState extends State<BarbersAdminScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _barbers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('barbers')
          .select('*')
          .order('name');
      setState(() {
        _barbers = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleAvailable(Map<String, dynamic> barber) async {
    final id = barber['id'];
    final current = (barber['is_available'] ?? true) == true;
    try {
      await Supabase.instance.client
          .from('barbers')
          .update({'is_available': !current})
          .eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _deleteBarber(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir barbeiro'),
        content: Text(
          'Tem certeza que deseja excluir "$name"?\n\n'
          'Todos os agendamentos, horários e bloqueios deste barbeiro serão apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final sb = Supabase.instance.client;
      await sb.from('appointments').delete().eq('barber_id', id);
      await sb.from('barber_availability').delete().eq('barber_id', id);
      await sb.from('blocked_slots').delete().eq('barber_id', id);
      try { await sb.from('barber_blocked_days').delete().eq('barber_id', id); } catch (_) {}
      await sb.from('barbers').delete().eq('id', id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erro ao excluir'),
          content: SelectableText(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Cria um usuário no Supabase via REST, sem afetar a sessão atual do admin.
  /// Retorna o user_id criado ou já existente.
  Future<String?> _createSupabaseUser(String email, String password) async {
    final res = await http.post(
      Uri.parse('${SupabaseConfig.supabaseUrl}/auth/v1/signup'),
      headers: {
        'apikey': SupabaseConfig.supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200 || res.statusCode == 201) {
      // Auto-confirm ON:  {"user": {"id": "..."}}
      // Email confirm:    {"id": "..."}
      if (body['user'] is Map) return body['user']['id']?.toString();
      return body['id']?.toString();
    }
    // Usuário já existe → busca pelo email na tabela users
    final msg = (body['msg'] ?? body['message'] ?? '').toString().toLowerCase();
    if (msg.contains('already') || msg.contains('existe')) {
      final row = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      return row?['id']?.toString();
    }
    throw Exception('Erro ao criar login: ${body['msg'] ?? res.body}');
  }

  Future<void> _sendPasswordReset(String email) async {
    final target = email.trim();
    // Sem e-mail não há como enviar a redefinição (caso de barbeiro com login
    // mas sem e-mail salvo na tabela). Avisa em vez de mandar vazio.
    if (target.isEmpty || !target.contains('@')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadastre o e-mail do barbeiro antes de redefinir a senha.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(target);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('E-mail de redefinição enviado para $target.')),
      );
    } catch (e) {
      if (!mounted) return;
      final lower = e.toString().toLowerCase();
      final msg = lower.contains('rate limit')
          ? 'Limite de envio de e-mails do Supabase atingido. Aguarde alguns minutos e tente novamente.'
          : 'Erro ao redefinir senha: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _createBarber({Map<String, dynamic>? existing}) async {
    final nameController =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final emailController =
        TextEditingController(text: existing?['email']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: existing?['phone']?.toString() ?? '');
    final passwordController = TextEditingController();
    final hasLogin = existing?['user_id'] != null;
    XFile? pickedImage;
    final specialtiesController = TextEditingController();
    List<String> specialties = existing?['specialties'] is List
        ? List<String>.from(existing!['specialties'])
        : <String>[];

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(existing == null ? 'Novo barbeiro' : 'Editar barbeiro'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Telefone'),
                ),
                const SizedBox(height: 8),
                if (!hasLogin) ...[
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Senha de acesso',
                      helperText: 'Deixe em branco se não tiver acesso ao painel',
                    ),
                  ),
                  const SizedBox(height: 4),
                ] else ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Acesso configurado',
                            style: TextStyle(fontSize: 13)),
                      ),
                      TextButton(
                        onPressed: () =>
                            _sendPasswordReset(emailController.text.trim()),
                        child: const Text('Redefinir senha',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setStateDialog) {
                    return Column(
                      children: [
                        SizedBox(
                          width: 96,
                          height: 96,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: pickedImage != null
                                ? Image.file(
                                    File(pickedImage!.path),
                                    fit: BoxFit.cover,
                                  )
                                : (existing?['image_url'] != null &&
                                      existing!['image_url']
                                          .toString()
                                          .isNotEmpty)
                                ? Image.network(
                                    existing['image_url'].toString(),
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceVariant,
                                    child: Icon(
                                      Icons.person,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final ImagePicker picker = ImagePicker();
                            final XFile? file = await picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 85,
                            );
                            if (file != null) {
                              setStateDialog(() => pickedImage = file);
                            }
                          },
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Selecionar foto'),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Especialidades',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: specialtiesController,
                                decoration: const InputDecoration(
                                  labelText: 'Adicionar especialidade',
                                ),
                                onSubmitted: (value) {
                                  final v = value.trim();
                                  if (v.isEmpty) return;
                                  if (!specialties.contains(v)) {
                                    setStateDialog(() {
                                      specialties.add(v);
                                      specialtiesController.clear();
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () {
                                final v = specialtiesController.text.trim();
                                if (v.isEmpty) return;
                                if (!specialties.contains(v)) {
                                  setStateDialog(() {
                                    specialties.add(v);
                                    specialtiesController.clear();
                                  });
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Adicionar'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: specialties
                                .map(
                                  (s) => Chip(
                                    label: Text(s),
                                    onDeleted: () {
                                      setStateDialog(() {
                                        specialties.remove(s);
                                      });
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  String? imageUrl;
                  if (pickedImage != null) {
                    try {
                      final ext = pickedImage!.path
                          .split('.')
                          .last
                          .toLowerCase();
                      final fileName =
                          'barber_${DateTime.now().millisecondsSinceEpoch}.$ext';
                      final filePath = 'avatars/$fileName';
                      final file = File(pickedImage!.path);
                      await Supabase.instance.client.storage
                          .from('fotos')
                          .upload(filePath, file);
                      imageUrl = Supabase.instance.client.storage
                          .from('fotos')
                          .getPublicUrl(filePath);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Falha ao enviar foto: $e. Salvando sem imagem.',
                            ),
                          ),
                        );
                      }
                    }
                  }
                  // Cria o login do barbeiro se email + senha foram preenchidos
                  String? resolvedUserId = existing?['user_id']?.toString();
                  final email = emailController.text.trim();
                  final password = passwordController.text.trim();
                  if (resolvedUserId == null && email.isNotEmpty && password.isNotEmpty) {
                    resolvedUserId = await _createSupabaseUser(email, password);
                  }

                  final data = <String, dynamic>{
                    'name': nameController.text.trim(),
                    'email': emailController.text.trim(),
                    'phone': phoneController.text.trim(),
                    if (specialties.isNotEmpty) 'specialties': specialties,
                    if (imageUrl != null) 'image_url': imageUrl,
                    'user_id': resolvedUserId,
                  };
                  if (existing != null) {
                    await Supabase.instance.client
                        .from('barbers')
                        .update(data)
                        .eq('id', existing['id'].toString());
                  } else {
                    data['is_available'] = true;
                    await Supabase.instance.client
                        .from('barbers')
                        .insert(data);
                  }
                  if (mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Erro: $e')));
                  }
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barbeiros'),
        actions: [
          IconButton(onPressed: _createBarber, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Erro: $_error'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _barbers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final b = _barbers[index];
                  final available = (b['is_available'] ?? true) == true;
                  return ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(b['name']?.toString() ?? ''),
                    subtitle: Text(b['email']?.toString() ?? ''),
                    onTap: () => _createBarber(existing: b),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: available,
                          onChanged: (_) => _toggleAvailable(b),
                        ),
                        IconButton(
                          tooltip: 'Editar',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _createBarber(existing: b),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Disponibilidade',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _openAvailabilityDialog(b),
                          icon: const Icon(Icons.schedule),
                        ),
                        IconButton(
                          tooltip: 'Excluir',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _deleteBarber(b['id'].toString(), b['name']?.toString() ?? ''),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

extension on _BarbersAdminScreenState {
  Future<void> _openAvailabilityDialog(Map<String, dynamic> barber) async {
    final barberId = (barber['id'] ?? '').toString();
    final theme = Theme.of(context);
    final Map<int, _DayAvailability> days = {
      1: _DayAvailability(
        true,
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 18, minute: 0),
      ),
      2: _DayAvailability(
        true,
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 18, minute: 0),
      ),
      3: _DayAvailability(
        true,
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 18, minute: 0),
      ),
      4: _DayAvailability(
        true,
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 18, minute: 0),
      ),
      5: _DayAvailability(
        true,
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 18, minute: 0),
      ),
      6: _DayAvailability(
        true,
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
      ),
      7: _DayAvailability(
        false,
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 12, minute: 0),
      ),
    };
    try {
      // Tenta carregar com as colunas de pausa; se não existirem, carrega sem elas
      List<Map<String, dynamic>> rows;
      try {
        final raw = await Supabase.instance.client
            .from('barber_availability')
            .select('day_of_week,start_time,end_time,is_available,break_start,break_end')
            .eq('barber_id', barberId);
        rows = List<Map<String, dynamic>>.from(raw);
      } catch (_) {
        final raw = await Supabase.instance.client
            .from('barber_availability')
            .select('day_of_week,start_time,end_time,is_available')
            .eq('barber_id', barberId);
        rows = List<Map<String, dynamic>>.from(raw);
      }
      for (final r in rows) {
        final dow = int.tryParse('${r['day_of_week']}') ?? -1;
        if (dow < 0) continue;
        final start = _parseTime('${r['start_time']}');
        final end = _parseTime('${r['end_time']}');
        final avail = (r['is_available'] ?? true) == true;
        final bsRaw = r['break_start']?.toString();
        final beRaw = r['break_end']?.toString();
        final hasBreak = bsRaw != null && bsRaw.isNotEmpty && bsRaw != 'null';
        days[dow == 0 ? 7 : dow] = _DayAvailability(
          avail, start, end,
          hasBreak: hasBreak,
          breakStart: hasBreak ? _parseTime(bsRaw) : const TimeOfDay(hour: 12, minute: 0),
          breakEnd: hasBreak && beRaw != null && beRaw != 'null' ? _parseTime(beRaw) : const TimeOfDay(hour: 14, minute: 0),
        );
      }
    } catch (_) {}

    bool applyAll = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text('Disponibilidade • ${barber['name'] ?? ''}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Switch(
                          value: applyAll,
                          onChanged: (v) {
                            setStateDialog(() => applyAll = v);
                            if (v) {
                              final base = days[1]!;
                              for (final k in days.keys) {
                                days[k] = _DayAvailability(
                                  base.enabled,
                                  base.start,
                                  base.end,
                                );
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Aplicar o mesmo horário para todos os dias',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._dayRows(days, setStateDialog),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      final sb = Supabase.instance.client;
                      final payload = <Map<String, dynamic>>[];
                      for (final entry in days.entries) {
                        final dow = entry.key;
                        final val = entry.value;
                        final row = <String, dynamic>{
                          'barber_id': barberId,
                          'day_of_week': dow == 7 ? 0 : dow,
                          'start_time': _fmt(val.start),
                          'end_time': _fmt(val.end),
                          'is_available': val.enabled,
                          'break_start': val.hasBreak ? _fmt(val.breakStart) : null,
                          'break_end': val.hasBreak ? _fmt(val.breakEnd) : null,
                        };
                        payload.add(row);
                      }
                      await sb.from('barber_availability').upsert(
                        payload,
                        onConflict: 'barber_id,day_of_week',
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Disponibilidade salva')),
                        );
                      }
                    } catch (e) {
                      if (!ctx.mounted) return;
                      showDialog(
                        context: ctx,
                        builder: (c) => AlertDialog(
                          title: const Text('Erro ao salvar'),
                          content: SelectableText(e.toString()),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _dayRows(
    Map<int, _DayAvailability> days,
    void Function(void Function()) setStateDialog,
  ) {
    final names = {
      1: 'Segunda',
      2: 'Terça',
      3: 'Quarta',
      4: 'Quinta',
      5: 'Sexta',
      6: 'Sábado',
      7: 'Domingo',
    };
    return days.entries.map((e) {
      final dow = e.key;
      final data = e.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(names[dow]!)),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Switch(
                    value: data.enabled,
                    onChanged: (v) => setStateDialog(
                      () => days[dow] = data.copyWith(enabled: v),
                    ),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: data.start,
                      );
                      if (picked != null) {
                        setStateDialog(
                          () => days[dow] = data.copyWith(start: picked),
                        );
                      }
                    },
                    child: Text('Início ${_label(data.start)}'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: data.end,
                      );
                      if (picked != null) {
                        setStateDialog(
                          () => days[dow] = data.copyWith(end: picked),
                        );
                      }
                    },
                    child: Text('Fim ${_label(data.end)}'),
                  ),
                  // ── Pausa / intervalo ──────────────────────────
                  FilterChip(
                    label: Text(data.hasBreak ? 'Pausa ativa' : 'Sem pausa'),
                    selected: data.hasBreak,
                    onSelected: (v) => setStateDialog(
                      () => days[dow] = data.copyWith(hasBreak: v),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (data.hasBreak) ...[
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        side: const BorderSide(color: Colors.orange),
                      ),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: data.breakStart,
                        );
                        if (picked != null) {
                          setStateDialog(
                            () => days[dow] = data.copyWith(breakStart: picked),
                          );
                        }
                      },
                      child: Text('Pausa ${_label(data.breakStart)}',
                          style: const TextStyle(color: Colors.orange)),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        side: const BorderSide(color: Colors.orange),
                      ),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: data.breakEnd,
                        );
                        if (picked != null) {
                          setStateDialog(
                            () => days[dow] = data.copyWith(breakEnd: picked),
                          );
                        }
                      },
                      child: Text('Retorno ${_label(data.breakEnd)}',
                          style: const TextStyle(color: Colors.orange)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  String _label(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  TimeOfDay _parseTime(String raw) {
    final parts = raw.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: h, minute: m);
  }
}

class _DayAvailability {
  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;
  final bool hasBreak;
  final TimeOfDay breakStart;
  final TimeOfDay breakEnd;
  const _DayAvailability(
    this.enabled,
    this.start,
    this.end, {
    this.hasBreak = false,
    this.breakStart = const TimeOfDay(hour: 12, minute: 0),
    this.breakEnd = const TimeOfDay(hour: 14, minute: 0),
  });
  _DayAvailability copyWith({
    bool? enabled,
    TimeOfDay? start,
    TimeOfDay? end,
    bool? hasBreak,
    TimeOfDay? breakStart,
    TimeOfDay? breakEnd,
  }) => _DayAvailability(
    enabled ?? this.enabled,
    start ?? this.start,
    end ?? this.end,
    hasBreak: hasBreak ?? this.hasBreak,
    breakStart: breakStart ?? this.breakStart,
    breakEnd: breakEnd ?? this.breakEnd,
  );
}
