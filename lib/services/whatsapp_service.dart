import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Configuração ──────────────────────────────────────────────────────────────

class WhatsappConfig {
  final String serverUrl; // ex: https://meu-servidor.railway.app
  final String apiKey;    // chave secreta definida no servidor
  final bool enabled;
  final String template;

  const WhatsappConfig({
    required this.serverUrl,
    required this.apiKey,
    required this.enabled,
    required this.template,
  });

  static const defaultTemplate =
      '❗ Resumo de seu agendamento:\n\n'
      '📅 Data: {{data}}\n'
      '🕐 Hora: {{hora}}\n'
      '✂️ Serviço: {{servico}}\n'
      '💈 Profissional: {{barbeiro}}\n'
      '💰 Valor: {{valor}}\n\n'
      'Obrigado, {{cliente}}! Te esperamos 👋';

  factory WhatsappConfig.empty() => const WhatsappConfig(
        serverUrl: '',
        apiKey: '',
        enabled: false,
        template: defaultTemplate,
      );

  bool get isConfigured => serverUrl.isNotEmpty && apiKey.isNotEmpty;

  String get normalizedUrl {
    final url = serverUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (url.startsWith('http')) return url;
    return 'https://$url';
  }

  WhatsappConfig copyWith({
    String? serverUrl,
    String? apiKey,
    bool? enabled,
    String? template,
  }) =>
      WhatsappConfig(
        serverUrl: serverUrl ?? this.serverUrl,
        apiKey: apiKey ?? this.apiKey,
        enabled: enabled ?? this.enabled,
        template: template ?? this.template,
      );
}

// ── Resultado ─────────────────────────────────────────────────────────────────

class WhatsappResult {
  final bool ok;
  final String? error;
  const WhatsappResult({required this.ok, this.error});
}

// ── Serviço ───────────────────────────────────────────────────────────────────

class WhatsappService {
  // ── Carregar config do Supabase ──────────────────────────────────────────

  static Future<WhatsappConfig> loadConfig() async {
    try {
      final rows = await Supabase.instance.client
          .from('app_settings')
          .select('key, value')
          .inFilter('key', [
        'wa_server_url',
        'wa_api_key',
        'wa_enabled',
        'wa_template',
      ]);
      final map = <String, String>{
        for (final r in (rows as List))
          r['key'] as String: r['value'] as String,
      };
      return WhatsappConfig(
        serverUrl: map['wa_server_url'] ?? '',
        apiKey: map['wa_api_key'] ?? '',
        enabled: map['wa_enabled'] == 'true',
        template: map['wa_template'] ?? WhatsappConfig.defaultTemplate,
      );
    } catch (_) {
      return WhatsappConfig.empty();
    }
  }

  // ── Salvar config ────────────────────────────────────────────────────────

  static Future<void> saveConfig(WhatsappConfig c) async {
    for (final row in [
      {'key': 'wa_server_url', 'value': c.serverUrl},
      {'key': 'wa_api_key', 'value': c.apiKey},
      {'key': 'wa_enabled', 'value': c.enabled.toString()},
      {'key': 'wa_template', 'value': c.template},
    ]) {
      await Supabase.instance.client
          .from('app_settings')
          .upsert(row, onConflict: 'key');
    }
  }

  // ── Montar mensagem ──────────────────────────────────────────────────────

  static String buildMessage({
    required String template,
    required String cliente,
    required String data,
    required String hora,
    required String servico,
    required String barbeiro,
    String valor = '',
  }) =>
      template
          .replaceAll('{{cliente}}', cliente)
          .replaceAll('{{data}}', data)
          .replaceAll('{{hora}}', hora)
          .replaceAll('{{servico}}', servico)
          .replaceAll('{{barbeiro}}', barbeiro)
          .replaceAll('{{valor}}', valor);

  // ── Enviar mensagem ──────────────────────────────────────────────────────

  static Future<WhatsappResult> sendMessage({
    required String phone,
    required String message,
    required WhatsappConfig config,
  }) async {
    if (!config.enabled || !config.isConfigured) {
      return const WhatsappResult(ok: false, error: 'WhatsApp não configurado.');
    }
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final fullPhone = clean.startsWith('55') ? clean : '55$clean';
    try {
      final res = await http.post(
        Uri.parse('${config.normalizedUrl}/send'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': config.apiKey,
        },
        body: jsonEncode({'phone': fullPhone, 'message': message}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) return const WhatsappResult(ok: true);

      // Tenta decodificar JSON; se falhar, usa mensagem genérica com código HTTP
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final msg = body['error']?.toString() ?? 'Erro ${res.statusCode}';
        return WhatsappResult(ok: false, error: msg);
      } catch (_) {
        if (res.statusCode == 503) {
          return const WhatsappResult(
            ok: false,
            error: 'WhatsApp desconectado — escaneie o QR code primeiro.',
          );
        }
        if (res.statusCode == 401) {
          return const WhatsappResult(
            ok: false,
            error: 'API Key inválida. Verifique a chave nas configurações.',
          );
        }
        return WhatsappResult(
          ok: false,
          error: 'Servidor retornou erro ${res.statusCode}.',
        );
      }
    } catch (e) {
      return WhatsappResult(ok: false, error: e.toString());
    }
  }

  // ── Verificar status do servidor ─────────────────────────────────────────

  static Future<ServerStatus> checkStatus(WhatsappConfig config) async {
    if (!config.isConfigured) {
      return ServerStatus(online: false, connected: false);
    }
    try {
      final res = await http.get(
        Uri.parse('${config.normalizedUrl}/status'),
        headers: {'x-api-key': config.apiKey},
      ).timeout(const Duration(seconds: 6));

      // Servidor respondeu — está online
      if (res.statusCode == 401) {
        return ServerStatus(online: true, connected: false, wrongKey: true);
      }
      if (res.statusCode != 200) {
        return ServerStatus(online: true, connected: false);
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return ServerStatus(
        online: true,
        connected: data['connected'] == true,
        phone: data['phone']?.toString(),
        hasQR: data['hasQR'] == true,
      );
    } catch (_) {
      // Servidor não respondeu
      return ServerStatus(online: false, connected: false);
    }
  }

  // ── Resetar sessão ──────────────────────────────────────────────────────

  static Future<WhatsappResult> resetSession(WhatsappConfig config) async {
    try {
      final res = await http.post(
        Uri.parse('${config.normalizedUrl}/reset-session'),
        headers: {'x-api-key': config.apiKey},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return const WhatsappResult(ok: true);
      return WhatsappResult(ok: false, error: 'Erro ${res.statusCode}');
    } catch (e) {
      return WhatsappResult(ok: false, error: e.toString());
    }
  }

  // ── Buscar QR code ───────────────────────────────────────────────────────

  static Future<String?> fetchQR(WhatsappConfig config) async {
    try {
      final res = await http.get(
        Uri.parse('${config.normalizedUrl}/qr'),
        headers: {'x-api-key': config.apiKey},
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['qr']?.toString();
    } catch (_) {
      return null;
    }
  }
}

// ── Status do servidor ────────────────────────────────────────────────────────

class ServerStatus {
  final bool online;
  final bool connected;
  final String? phone;
  final bool hasQR;
  final bool wrongKey;

  ServerStatus({
    required this.online,
    required this.connected,
    this.phone,
    this.hasQR = false,
    this.wrongKey = false,
  });
}
