import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

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

  Future<void> _deleteBarber(String id) async {
    try {
      await Supabase.instance.client.from('barbers').delete().eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _createBarber({Map<String, dynamic>? existing}) async {
    final nameController =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final emailController =
        TextEditingController(text: existing?['email']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: existing?['phone']?.toString() ?? '');
    // Email de login vinculado (buscado na tabela users pelo user_id atual)
    String? linkedLoginEmail;
    if (existing?['user_id'] != null) {
      try {
        final row = await Supabase.instance.client
            .from('users')
            .select('email')
            .eq('id', existing!['user_id'].toString())
            .maybeSingle();
        linkedLoginEmail = row?['email']?.toString();
      } catch (_) {}
    }
    final loginEmailController =
        TextEditingController(text: linkedLoginEmail ?? '');
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
                TextField(
                  controller: loginEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email de login (para acesso admin)',
                    hintText: 'email@exemplo.com',
                    helperText: 'Deixe em branco se não tiver acesso',
                  ),
                ),
                const SizedBox(height: 12),
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
                  // Resolve user_id pelo email de login digitado
                  final loginEmail = loginEmailController.text.trim();
                  String? resolvedUserId = existing?['user_id']?.toString();
                  if (loginEmail.isNotEmpty && loginEmail != linkedLoginEmail) {
                    try {
                      final userRow = await Supabase.instance.client
                          .from('users')
                          .select('id')
                          .eq('email', loginEmail)
                          .maybeSingle();
                      if (userRow != null) {
                        resolvedUserId = userRow['id'].toString();
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Email de login não encontrado. O barbeiro precisa fazer login uma vez antes de ser vinculado.'),
                        ));
                      }
                    } catch (_) {}
                  } else if (loginEmail.isEmpty) {
                    resolvedUserId = null;
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
                          onPressed: () => _deleteBarber(b['id'].toString()),
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
      final rows = await Supabase.instance.client
          .from('barber_availability')
          .select('*')
          .eq('barber_id', barberId);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final dow = int.tryParse('${r['day_of_week']}') ?? -1;
        if (dow < 0) continue;
        final start = _parseTime('${r['start_time']}');
        final end = _parseTime('${r['end_time']}');
        final avail = (r['is_available'] ?? true) == true;
        days[dow == 0 ? 7 : dow] = _DayAvailability(avail, start, end);
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
                      await Supabase.instance.client
                          .from('barber_availability')
                          .delete()
                          .eq('barber_id', barberId);
                      final payload = <Map<String, dynamic>>[];
                      for (final entry in days.entries) {
                        final dow = entry.key;
                        final val = entry.value;
                        payload.add({
                          'barber_id': barberId,
                          'day_of_week': dow == 7 ? 0 : dow,
                          'start_time': _fmt(val.start),
                          'end_time': _fmt(val.end),
                          'is_available': val.enabled,
                        });
                      }
                      await Supabase.instance.client
                          .from('barber_availability')
                          .insert(payload);
                      if (mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Disponibilidade salva'),
                          ),
                        );
                      }
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
  const _DayAvailability(this.enabled, this.start, this.end);
  _DayAvailability copyWith({
    bool? enabled,
    TimeOfDay? start,
    TimeOfDay? end,
  }) => _DayAvailability(
    enabled ?? this.enabled,
    start ?? this.start,
    end ?? this.end,
  );
}
