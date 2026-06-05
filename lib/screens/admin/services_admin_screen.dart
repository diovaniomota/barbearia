import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
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
    final current = (service['is_active'] ?? true) == true;
    try {
      await Supabase.instance.client
          .from('services')
          .update({'is_active': !current})
          .eq('id', service['id'].toString());
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir serviço?'),
        content: const Text('Esta ação não pode ser desfeita.'),
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
      await Supabase.instance.client.from('services').delete().eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      builder: (_) => _ServiceFormDialog(existing: existing),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serviços'),
        actions: [
          IconButton(
            tooltip: 'Novo serviço',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Erro: $_error'))
          : RefreshIndicator(
              onRefresh: _load,
              child: _services.isEmpty
                  ? const Center(child: Text('Nenhum serviço cadastrado.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _services.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final s = _services[i];
                        final active = (s['is_active'] ?? true) == true;
                        final imageUrl =
                            (s['image_url'] ?? '').toString().trim();
                        final price =
                            (s['price'] as num? ?? 0).toDouble();

                        return Card(
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.fromLTRB(12, 8, 8, 8),
                            leading: _Thumb(url: imageUrl),
                            title: Text(
                              s['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              NumberFormat.currency(
                                locale: 'pt_BR',
                                symbol: 'R\$',
                              ).format(price),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: active,
                                  onChanged: (_) => _toggleActive(s),
                                ),
                                IconButton(
                                  tooltip: 'Editar',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _openForm(existing: s),
                                ),
                                IconButton(
                                  tooltip: 'Excluir',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      _delete(s['id'].toString()),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ── Thumbnail da lista ────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    if (url.isEmpty) {
      return _box(color, child: const Icon(Icons.content_cut, size: 22));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _box(color, child: const Icon(Icons.broken_image_outlined, size: 22)),
      ),
    );
  }

  Widget _box(Color color, {required Widget child}) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

// ── Formulário (criar / editar) ───────────────────────────────────────────────

class _ServiceFormDialog extends StatefulWidget {
  const _ServiceFormDialog({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<_ServiceFormDialog> {
  final _nameCtr = TextEditingController();
  final _priceCtr = TextEditingController();

  String? _currentImageUrl;
  XFile? _pickedImage;
  Uint8List? _pickedBytes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtr.text = e['name']?.toString() ?? '';
      final price = (e['price'] as num? ?? 0).toDouble();
      _priceCtr.text = NumberFormat.currency(
        locale: 'pt_BR',
        symbol: 'R\$',
      ).format(price);
      _currentImageUrl = (e['image_url'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _priceCtr.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedImage = picked;
        _pickedBytes = bytes;
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImage == null) return _currentImageUrl;

    final bytes = await _pickedImage!.readAsBytes();
    final ext = _pickedImage!.name.split('.').last.toLowerCase();
    final mime = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      await Supabase.instance.client.storage
          .from('service-images')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
      return Supabase.instance.client.storage
          .from('service-images')
          .getPublicUrl(fileName);
    } catch (e) {
      _uploadError = e.toString();
      return _currentImageUrl;
    }
  }

  String? _uploadError;

  Future<void> _save() async {
    final name = _nameCtr.text.trim();
    if (name.isEmpty) {
      setState(() => _saveError = 'O nome é obrigatório.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
      _uploadError = null;
    });

    try {
      final imageUrl = await _uploadImage();

      final digits = _priceCtr.text.replaceAll(RegExp(r'[^0-9]'), '');
      final price = digits.isEmpty ? 0.0 : double.parse(digits) / 100.0;

      final data = <String, dynamic>{
        'name': name,
        'price': price,
        if (imageUrl != null) 'image_url': imageUrl,
      };

      if (widget.existing != null) {
        await Supabase.instance.client
            .from('services')
            .update(data)
            .eq('id', widget.existing!['id'].toString());
      } else {
        await Supabase.instance.client.from('services').insert(data);
      }

      if (!mounted) return;

      if (_uploadError != null) {
        // Dados salvos mas imagem falhou — avisa e fecha
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Salvo! Mas a foto falhou: $_uploadError'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveError = e.toString();
          _saving = false;
        });
      }
    }
  }

  String? _saveError;

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Editar serviço' : 'Novo serviço'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Foto ────────────────────────────────────
              GestureDetector(
                onTap: _saving ? null : _pickImage,
                child: _ImagePicker(
                  pickedBytes: _pickedBytes,
                  currentUrl: _currentImageUrl,
                ),
              ),
              const SizedBox(height: 16),

              // ── Erro de salvamento ───────────────────────
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),

              // ── Nome ────────────────────────────────────
              TextField(
                controller: _nameCtr,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nome *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // ── Preço ──────────────────────────────────
              TextField(
                controller: _priceCtr,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Preço (R\$)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.isEmpty) {
                    _priceCtr.text = '';
                    return;
                  }
                  final val = double.parse(digits) / 100.0;
                  final text = NumberFormat.currency(
                    locale: 'pt_BR',
                    symbol: 'R\$',
                  ).format(val);
                  _priceCtr.value = TextEditingValue(
                    text: text,
                    selection: TextSelection.collapsed(offset: text.length),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

// ── Widget de seleção de imagem ───────────────────────────────────────────────

class _ImagePicker extends StatelessWidget {
  const _ImagePicker({required this.pickedBytes, required this.currentUrl});

  final Uint8List? pickedBytes;
  final String? currentUrl;

  @override
  Widget build(BuildContext context) {
    final hasNetwork =
        pickedBytes == null && (currentUrl?.isNotEmpty ?? false);
    final hasLocal = pickedBytes != null;

    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          if (hasLocal)
            Image.memory(pickedBytes!, fit: BoxFit.cover)
          else if (hasNetwork)
            Image.network(
              currentUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _Placeholder(),
            )
          else
            _Placeholder(),

          // Camera button overlay
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_camera, color: Colors.white, size: 15),
                  SizedBox(width: 5),
                  Text(
                    'Alterar foto',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          size: 34,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 6),
        Text(
          'Toque para adicionar foto',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
