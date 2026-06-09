import 'dart:convert';
import 'dart:async';

import 'package:barbearia/services/whatsapp_service.dart';
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class WhatsappAdminScreen extends StatefulWidget {
  const WhatsappAdminScreen({super.key});

  @override
  State<WhatsappAdminScreen> createState() => _WhatsappAdminScreenState();
}

class _WhatsappAdminScreenState extends State<WhatsappAdminScreen> {
  final _urlCtr = TextEditingController();
  final _keyCtr = TextEditingController();
  final _tmplCtr = TextEditingController();
  final _testCtr = TextEditingController();

  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;

  ServerStatus? _status;
  String? _qrBase64;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _urlCtr.dispose();
    _keyCtr.dispose();
    _tmplCtr.dispose();
    _testCtr.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await WhatsappService.loadConfig();
    if (!mounted) return;
    setState(() {
      _urlCtr.text = config.serverUrl;
      _keyCtr.text = config.apiKey;
      _tmplCtr.text = config.template;
      _enabled = config.enabled;
      _loading = false;
    });
    if (config.isConfigured) _startPolling();
  }

  WhatsappConfig get _currentConfig => WhatsappConfig(
    serverUrl: _urlCtr.text.trim(),
    apiKey: _keyCtr.text.trim(),
    enabled: _enabled,
    template: _tmplCtr.text.trim(),
  );

  // Verifica status + QR a cada 4 segundos enquanto não conectado
  void _startPolling() {
    _pollTimer?.cancel();
    _refreshStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_status?.connected == true) {
        _pollTimer?.cancel();
      } else {
        _refreshStatus();
      }
    });
  }

  Future<void> _refreshStatus() async {
    final config = _currentConfig;
    if (!config.isConfigured) return;

    final status = await WhatsappService.checkStatus(config);
    if (!mounted) return;
    setState(() => _status = status);

    if (status.online && !status.connected) {
      final qr = await WhatsappService.fetchQR(config);
      if (!mounted) return;
      setState(() => _qrBase64 = qr);
    } else if (status.connected) {
      setState(() => _qrBase64 = null);
    }
  }

  Future<void> _resetSession() async {
    final config = _currentConfig;
    if (!config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configure a URL e API Key primeiro.')),
      );
      return;
    }
    if (_status?.online != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Servidor está offline. Não é possível resetar a sessão agora.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resetar sessão?'),
        content: const Text(
          'Isso apaga a sessão salva no servidor e gera um novo QR Code. '
          'Você precisará escanear novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resetar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await WhatsappService.resetSession(config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? 'Sessão resetada! Aguarde o QR.'
                : 'Erro: ${result.error}',
          ),
          backgroundColor: result.ok ? Colors.green : Colors.red,
        ),
      );
      if (result.ok) _startPolling();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await WhatsappService.saveConfig(_currentConfig);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuração salva!')));
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTest() async {
    final phone = _testCtr.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Digite um número.')));
      return;
    }
    setState(() => _testing = true);
    final msg = WhatsappService.buildMessage(
      template: _currentConfig.template,
      cliente: 'João Teste',
      data: '01/07/2025',
      hora: '10:00',
      servico: 'Corte Masculino',
      barbeiro: 'Carlos',
      valor: 'R\$ 50,00',
    );
    final result = await WhatsappService.sendMessage(
      phone: phone,
      message: msg,
      config: _currentConfig,
    );
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.ok ? '✓ Enviado!' : 'Erro: ${result.error}'),
        backgroundColor: result.ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status ───────────────────────────────────────
          _StatusCard(
            status: _status,
            enabled: _enabled,
            onToggle: (v) {
              setState(() => _enabled = v);
            },
          ),
          const SizedBox(height: 20),

          // ── QR Code ──────────────────────────────────────
          if (_status?.online == true && !(_status?.connected == true))
            _QrCard(qrBase64: _qrBase64, onRefresh: _refreshStatus),
          if (_status?.online == true && !(_status?.connected == true))
            const SizedBox(height: 20),

          // ── Servidor ─────────────────────────────────────
          Text(
            'Servidor WhatsApp',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Suba o servidor em Railway, Render ou qualquer VPS e cole a URL abaixo.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtr,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL do servidor',
              hintText: 'https://meu-servidor.railway.app',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _keyCtr,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'Chave definida no .env do servidor',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.wifi_find_outlined, size: 18),
            label: const Text('Conectar / verificar'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _resetSession,
            icon: const Icon(Icons.restart_alt, size: 18, color: Colors.red),
            label: const Text(
              'Resetar sessão (novo QR)',
              style: TextStyle(color: Colors.red),
            ),
          ),
          const SizedBox(height: 16),

          // ── Template ─────────────────────────────────────
          Text(
            'Mensagem automática',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          _VariableChips(controller: _tmplCtr),
          const SizedBox(height: 8),
          TextField(
            controller: _tmplCtr,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Texto da mensagem…',
            ),
          ),
          const SizedBox(height: 24),

          // ── Teste ────────────────────────────────────────
          Text(
            'Testar envio',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _testCtr,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    MaskTextInputFormatter(
                      mask: '(##) #####-####',
                      filter: {'#': RegExp(r'[0-9]')},
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Número WhatsApp',
                    hintText: '(11) 99999-9999',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.send_to_mobile_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _testing ? null : _sendTest,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 18),
                label: const Text('Enviar'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Salvar configuração'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.enabled,
    required this.onToggle,
  });

  final ServerStatus? status;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final s = status;
    Color color;
    String label;
    IconData icon;

    if (s == null) {
      color = Colors.grey;
      label = 'Não configurado';
      icon = Icons.chat_bubble_outline_rounded;
    } else if (!s.online) {
      color = Colors.red;
      label = 'Servidor offline';
      icon = Icons.cloud_off_rounded;
    } else if (s.wrongKey) {
      color = Colors.red;
      label = 'API Key inválida — verifique a chave';
      icon = Icons.key_off_outlined;
    } else if (!s.connected) {
      color = Colors.orange;
      label = 'Online — escaneie o QR code';
      icon = Icons.qr_code_rounded;
    } else {
      color = Colors.green;
      label = s.phone != null ? 'Conectado: +${s.phone}' : 'Conectado';
      icon = Icons.chat_bubble_rounded;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mensagens automáticas',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            Switch(value: enabled, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}

// ── QR Card ───────────────────────────────────────────────────────────────────

class _QrCard extends StatelessWidget {
  const _QrCard({required this.qrBase64, required this.onRefresh});

  final String? qrBase64;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Escaneie com o WhatsApp do número da barbearia',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Atualizar QR',
                  onPressed: onRefresh,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (qrBase64 == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  base64Decode(qrBase64!.split(',').last),
                  width: 220,
                  height: 220,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Abra o WhatsApp → Dispositivos conectados → Conectar dispositivo',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chips de variáveis ────────────────────────────────────────────────────────

class _VariableChips extends StatelessWidget {
  const _VariableChips({required this.controller});
  final TextEditingController controller;

  void _insert(String variable) {
    final sel = controller.selection;
    final text = controller.text;
    final pos = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? pos : sel.end;
    final newText = text.replaceRange(pos, end, variable);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + variable.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children:
          [
                '{{cliente}}',
                '{{data}}',
                '{{hora}}',
                '{{servico}}',
                '{{barbeiro}}',
                '{{valor}}',
              ]
              .map(
                (v) => ActionChip(
                  label: Text(v, style: const TextStyle(fontSize: 11)),
                  onPressed: () => _insert(v),
                ),
              )
              .toList(),
    );
  }
}
