import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServicesAdminScreen extends StatefulWidget {
  const ServicesAdminScreen({super.key});

  @override
  State<ServicesAdminScreen> createState() => _ServicesAdminScreenState();
}

class _ServicesAdminScreenState extends State<ServicesAdminScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _services = [];

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
          .from('services')
          .select('*')
          .order('name');
      setState(() {
        _services = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> service) async {
    final id = service['id'];
    final current = (service['is_active'] ?? true) == true;
    try {
      await Supabase.instance.client
          .from('services')
          .update({'is_active': !current})
          .eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _deleteService(String id) async {
    try {
      await Supabase.instance.client.from('services').delete().eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _createService() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final durationController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Novo serviço'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome')),
                TextField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Descrição')),
                TextField(controller: priceController, decoration: const InputDecoration(labelText: 'Preço')), 
                TextField(controller: durationController, decoration: const InputDecoration(labelText: 'Duração (min)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final desc = descriptionController.text.trim();
                final price = double.tryParse(priceController.text.replaceAll(',', '.')) ?? 0;
                final duration = int.tryParse(durationController.text) ?? 0;
                try {
                  await Supabase.instance.client.from('services').insert({
                    'name': name,
                    'description': desc,
                    'price': price,
                    'duration_minutes': duration,
                    'is_active': true,
                  });
                  if (mounted) Navigator.pop(ctx);
                  await _load();
                } on PostgrestException catch (_) {
                  try {
                    await Supabase.instance.client.from('services').insert({
                      'name': name,
                      'descricao': desc,
                      'price': price,
                      'duracao': duration,
                      'is_active': true,
                    });
                    if (mounted) Navigator.pop(ctx);
                    await _load();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e')),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro: $e')),
                    );
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
        title: const Text('Serviços'),
        actions: [
          IconButton(onPressed: _createService, icon: const Icon(Icons.add)),
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
                    itemCount: _services.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final s = _services[index];
                      final active = (s['is_active'] ?? true) == true;
                      return ListTile(
                        leading: const Icon(Icons.content_cut),
                        title: Text(s['name']?.toString() ?? ''),
                        subtitle: Text(s['description']?.toString() ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(value: active, onChanged: (_) => _toggleActive(s)),
                            IconButton(
                              tooltip: 'Excluir',
                              onPressed: () => _deleteService(s['id'].toString()),
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
