import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Configuração ──────────────────────────────────────────────────────────────

class WhatsappConfig {
  final String serverUrl; // ex: https://meu-servidor.railway.app
  final String apiKey; // chave secreta definida no servidor
  final bool enabled;
  final String template;
  final int reminderNormalHours;   // horas antes para lembrete (clientes normais)
  final String normalTemplate24h;  // lembrete 24h antes para clientes normais
  final String planTemplate24h;    // lembrete 24h antes para clientes do plano
  final String planTemplate1h;     // lembrete no horário configurado para clientes do plano

  const WhatsappConfig({
    required this.serverUrl,
    required this.apiKey,
    required this.enabled,
    required this.template,
    this.reminderNormalHours = 1,
    this.normalTemplate24h = defaultNormalTemplate24h,
    this.planTemplate24h   = defaultPlanTemplate24h,
    this.planTemplate1h    = defaultPlanTemplate1h,
  });

  static const defaultTemplate =
      '❗ Resumo de seu agendamento:\n\n'
      '📅 Data: {{data}}\n'
      '🕐 Hora: {{hora}}\n'
      '✂️ Serviço: {{servico}}\n'
      '💈 Profissional: {{barbeiro}}\n'
      '💰 Valor: {{valor}}\n\n'
      'Obrigado, {{cliente}}! Te esperamos 👋';

  static const defaultNormalTemplate24h =
      '📅 Lembrete do seu agendamento!\n\n'
      'Olá {{cliente}}! Seu horário é amanhã às {{hora}}.\n'
      '✂️ Serviço: {{servico}}\n'
      '💈 Profissional: {{barbeiro}}\n\n'
      'Te esperamos amanhã! 👋';

  static const defaultPlanTemplate24h =
      '📅 Lembrete do seu plano!\n\n'
      'Olá {{cliente}}! Seu horário é amanhã às {{hora}}.\n'
      '✂️ Serviço: {{servico}}\n'
      '💈 Profissional: {{barbeiro}}\n\n'
      'Te esperamos amanhã! 👋';

  static const defaultPlanTemplate1h =
      '⏰ Quase na hora!\n\n'
      'Olá {{cliente}}! Seu horário de plano é hoje às {{hora}}.\n'
      '✂️ Serviço: {{servico}}\n'
      '💈 Profissional: {{barbeiro}}\n\n'
      'Te esperamos daqui a pouco! 🙌';

  factory WhatsappConfig.empty() => const WhatsappConfig(
    serverUrl: '',
    apiKey: '',
    enabled: false,
    template: defaultTemplate,
    normalTemplate24h: defaultNormalTemplate24h,
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
    int? reminderNormalHours,
    String? normalTemplate24h,
    String? planTemplate24h,
    String? planTemplate1h,
  }) => WhatsappConfig(
    serverUrl:            serverUrl            ?? this.serverUrl,
    apiKey:               apiKey               ?? this.apiKey,
    enabled:              enabled              ?? this.enabled,
    template:             template             ?? this.template,
    reminderNormalHours:  reminderNormalHours  ?? this.reminderNormalHours,
    normalTemplate24h:    normalTemplate24h    ?? this.normalTemplate24h,
    planTemplate24h:      planTemplate24h      ?? this.planTemplate24h,
    planTemplate1h:       planTemplate1h       ?? this.planTemplate1h,
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
            'reminder_normal_hours',
            'wa_reminder_template_24h',
            'wa_plan_reminder_template_24h',
            'wa_plan_reminder_template_1h',
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
        reminderNormalHours:
            int.tryParse(map['reminder_normal_hours'] ?? '1') ?? 1,
        normalTemplate24h: map['wa_reminder_template_24h'] ??
            WhatsappConfig.defaultNormalTemplate24h,
        planTemplate24h: map['wa_plan_reminder_template_24h'] ??
            WhatsappConfig.defaultPlanTemplate24h,
        planTemplate1h: map['wa_plan_reminder_template_1h'] ??
            WhatsappConfig.defaultPlanTemplate1h,
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
      {'key': 'reminder_normal_hours', 'value': c.reminderNormalHours.toString()},
      {'key': 'wa_reminder_template_24h', 'value': c.normalTemplate24h},
      {'key': 'wa_plan_reminder_template_24h', 'value': c.planTemplate24h},
      {'key': 'wa_plan_reminder_template_1h', 'value': c.planTemplate1h},
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
  }) => template
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
      return const WhatsappResult(
        ok: false,
        error: 'WhatsApp não configurado.',
      );
    }
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final fullPhone = clean.startsWith('55') ? clean : '55$clean';
    try {
      final res = await http
          .post(
            Uri.parse('${config.normalizedUrl}/send'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': config.apiKey,
            },
            body: jsonEncode({'phone': fullPhone, 'message': message}),
          )
          .timeout(const Duration(seconds: 10));

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
      final res = await http
          .get(
            Uri.parse('${config.normalizedUrl}/status'),
            headers: {'x-api-key': config.apiKey},
          )
          .timeout(const Duration(seconds: 6));

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
      final res = await http
          .post(
            Uri.parse('${config.normalizedUrl}/reset-session'),
            headers: {'x-api-key': config.apiKey},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return const WhatsappResult(ok: true);
      return WhatsappResult(ok: false, error: 'Erro ${res.statusCode}');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('failed to fetch') ||
          msg.contains('socketexception') ||
          msg.contains('connection refused')) {
        return const WhatsappResult(
          ok: false,
          error: 'Servidor não está acessível. Verifique se ele está rodando.',
        );
      }
      if (msg.contains('timeout') || msg.contains('timed out')) {
        return const WhatsappResult(
          ok: false,
          error: 'Servidor demorou demais para responder (timeout).',
        );
      }
      return WhatsappResult(ok: false, error: e.toString());
    }
  }

  // ── Buscar QR code ───────────────────────────────────────────────────────

  static Future<String?> fetchQR(WhatsappConfig config) async {
    try {
      final res = await http
          .get(
            Uri.parse('${config.normalizedUrl}/qr'),
            headers: {'x-api-key': config.apiKey},
          )
          .timeout(const Duration(seconds: 6));
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
