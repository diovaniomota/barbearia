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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _deleteBarber(String id) async {
    try {
      await Supabase.instance.client.from('barbers').delete().eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _createBarber() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    XFile? pickedImage;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Novo barbeiro'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome')),
                TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Telefone')),
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
                            child: pickedImage == null
                                ? Container(
                                    color: Theme.of(context).colorScheme.surfaceVariant,
                                    child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                                  )
                                : Image.file(File(pickedImage!.path), fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final ImagePicker picker = ImagePicker();
                            final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                            if (file != null) {
                              setStateDialog(() => pickedImage = file);
                            }
                          },
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Selecionar foto'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  String? imageUrl;
                  if (pickedImage != null) {
                    final ext = pickedImage!.path.split('.').last.toLowerCase();
                    final fileName = 'barber_${DateTime.now().millisecondsSinceEpoch}.$ext';
                    final filePath = 'avatars/$fileName';
                    final file = File(pickedImage!.path);
                    await Supabase.instance.client.storage.from('barbers').upload(filePath, file);
                    imageUrl = Supabase.instance.client.storage.from('barbers').getPublicUrl(filePath);
                  }
                  await Supabase.instance.client.from('barbers').insert({
                    'name': nameController.text.trim(),
                    'email': emailController.text.trim(),
                    'phone': phoneController.text.trim(),
                    'is_available': true,
                    if (imageUrl != null) 'image_url': imageUrl,
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(value: available, onChanged: (_) => _toggleAvailable(b)),
                            IconButton(
                              tooltip: 'Excluir',
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
