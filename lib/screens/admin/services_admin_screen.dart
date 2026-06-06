import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:barbearia/models/service.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _serviceImagesBucket = 'fotos';
const _serviceImagesFolder = 'services';
const _legacyServiceImagesBucket = 'service-images';

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
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
                        final imageUrl = Service.parseImageUrl(s);
                        final price = (s['price'] as num? ?? 0).toDouble();

                        return Card(
                          child: ListTile(
                            minLeadingWidth: 68,
                            contentPadding: const EdgeInsets.fromLTRB(
                              12,
                              8,
                              8,
                              8,
                            ),
                            leading: _Thumb(url: imageUrl),
                            title: Text(
                              s['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  NumberFormat.currency(
                                    locale: 'pt_BR',
                                    symbol: 'R\$',
                                  ).format(price),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  imageUrl.isEmpty
                                      ? '⚠ SEM URL no banco'
                                      : 'Foto salva',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: imageUrl.isEmpty
                                        ? Colors.redAccent
                                        : Colors.greenAccent,
                                  ),
                                ),
                              ],
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
                                  onPressed: () => _delete(s['id'].toString()),
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
  static const double size = 64;

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
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _box(
            color,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, _, _) => _box(
          color,
          child: const Icon(Icons.broken_image_outlined, size: 22),
        ),
      ),
    );
  }

  Widget _box(Color color, {required Widget child}) {
    return Container(
      width: size,
      height: size,
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

  String? _saveError;

  Future<String> _uploadImage() async {
    final picked = _pickedImage;
    if (picked == null) {
      throw StateError('Nenhuma foto selecionada.');
    }

    final bytes = _pickedBytes ?? await picked.readAsBytes();
    final ext = _detectImageExtension(picked, bytes);
    final mime = _mimeForExtension(ext);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'service_$timestamp.$ext';
    final filePath = '$_serviceImagesFolder/$fileName';

    try {
      return await _uploadToBucket(
        bucket: _serviceImagesBucket,
        path: filePath,
        bytes: bytes,
        mime: mime,
      );
    } catch (primaryError) {
      try {
        return await _uploadImageFromLegacyBucket();
      } catch (legacyError) {
        final message = _formatStorageUploadError(
          primaryError: primaryError,
          legacyError: legacyError,
        );
        debugPrint(message);
        throw Exception(message);
      }
    }
  }

  String _formatStorageUploadError({
    required Object primaryError,
    required Object legacyError,
  }) {
    final primary = _storageErrorDetails(primaryError);
    final legacy = _storageErrorDetails(legacyError);
    final combined = '$primary $legacy'.toLowerCase();

    String hint;
    if (combined.contains('mime') ||
        combined.contains('content-type') ||
        combined.contains('not supported') ||
        combined.contains('unsupported')) {
      hint =
          'O bucket nao esta aceitando este tipo de imagem. Rode novamente '
          'lib/supabase/service_images_storage_migration.sql no SQL Editor do Supabase.';
    } else if (combined.contains('row-level security') ||
        combined.contains('policy') ||
        combined.contains('unauthorized') ||
        combined.contains('forbidden')) {
      hint =
          'Faltou permissao no Storage. Rode novamente '
          'lib/supabase/service_images_storage_migration.sql no SQL Editor do Supabase e entre no admin de novo.';
    } else if (combined.contains('bucket') || combined.contains('not found')) {
      hint =
          'O bucket de fotos nao existe ou esta em outro projeto. Rode '
          'lib/supabase/service_images_storage_migration.sql no projeto uebvtbgvsyzbyzdilren.';
    } else {
      hint =
          'Rode lib/supabase/service_images_storage_migration.sql no SQL Editor do Supabase e tente salvar novamente.';
    }

    return '$hint\nErro em "$_serviceImagesBucket": $primary\nErro em "$_legacyServiceImagesBucket": $legacy';
  }

  String _storageErrorDetails(Object error) {
    if (error is StorageException) {
      final parts = <String>[
        if (error.statusCode != null) 'status ${error.statusCode}',
        error.message,
        if (error.error != null) error.error!,
      ];
      return parts.join(' - ');
    }
    return error.toString();
  }

  Future<String> _uploadToBucket({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mime,
  }) async {
    if (kIsWeb) {
      await _uploadToBucketWithHttp(
        bucket: bucket,
        path: path,
        bytes: bytes,
        mime: mime,
      );
      return Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
    }

    await Supabase.instance.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );

    return Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
  }

  Future<void> _uploadToBucketWithHttp({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mime,
  }) async {
    final storage = Supabase.instance.client.storage;
    final uri = Uri.parse('${storage.url}/object/$bucket/$path');
    final headers = <String, String>{
      ...storage.headers,
      'content-type': mime,
      'x-upsert': 'true',
    };

    final response = await http.post(uri, headers: headers, body: bytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw StorageException(
      response.body.isEmpty
          ? response.reasonPhrase ?? 'Upload recusado'
          : response.body,
      statusCode: response.statusCode.toString(),
      error: 'HTTP ${response.statusCode}',
    );
  }

  String _detectImageExtension(XFile file, Uint8List bytes) {
    final mime = file.mimeType?.toLowerCase();
    if (mime == 'image/jpeg') return 'jpg';
    if (mime == 'image/png') return 'png';
    if (mime == 'image/webp') return 'webp';
    if (mime == 'image/gif') return 'gif';

    for (final candidate in [file.name, file.path]) {
      final ext = candidate.split('.').last.toLowerCase();
      if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) {
        return ext == 'jpeg' ? 'jpg' : ext;
      }
    }

    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    }
    if (bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length > 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length > 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'gif';
    }

    return 'jpg';
  }

  String _mimeForExtension(String ext) {
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  Future<String> _uploadImageFromLegacyBucket() async {
    final bytes = await _pickedImage!.readAsBytes();

    // On web, XFile.name can be a blob URL — detect extension from bytes
    String ext = _pickedImage!.name.split('.').last.toLowerCase();
    if (ext.length > 5 || ext.contains('/') || ext.contains(':')) {
      ext = (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8)
          ? 'jpg'
          : 'png';
    }

    final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';

    await Supabase.instance.client.storage
        .from(_legacyServiceImagesBucket)
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );

    return Supabase.instance.client.storage
        .from(_legacyServiceImagesBucket)
        .getPublicUrl(fileName);
  }

  Future<void> _save() async {
    final name = _nameCtr.text.trim();
    if (name.isEmpty) {
      setState(() => _saveError = 'O nome é obrigatório.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    // 1. Upload da imagem (se foi selecionada uma nova)
    String? imageUrl = _currentImageUrl?.trim().isNotEmpty == true
        ? _currentImageUrl!.trim()
        : null;
    if (_pickedImage != null) {
      try {
        imageUrl = await _uploadImage();
      } catch (e) {
        if (mounted) {
          setState(() {
            _saveError = 'Erro no upload da foto: ${e.toString()}';
            _saving = false;
          });
        }
        return;
      }
    }

    // 2. Salva no banco
    try {
      final digits = _priceCtr.text.replaceAll(RegExp(r'[^0-9]'), '');
      final price = digits.isEmpty ? 0.0 : double.parse(digits) / 100.0;

      final data = <String, dynamic>{
        'name': name,
        'price': price,
        'image_url': imageUrl, // always include (null clears, URL saves)
      };

      dynamic savedRows;
      if (widget.existing != null) {
        savedRows = await Supabase.instance.client
            .from('services')
            .update(data)
            .eq('id', widget.existing!['id'].toString())
            .select('id,image_url');
      } else {
        savedRows = await Supabase.instance.client
            .from('services')
            .insert(data)
            .select('id,image_url');
      }

      final updated = savedRows is List && savedRows.isNotEmpty;
      if (!updated) {
        throw Exception(
          'O Supabase nao atualizou o servico. Rode novamente '
          'lib/supabase/service_images_storage_migration.sql no SQL Editor '
          'e tente salvar a foto de novo.',
        );
      }

      if (!mounted) return;
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
    final hasNetwork = pickedBytes == null && (currentUrl?.isNotEmpty ?? false);
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
