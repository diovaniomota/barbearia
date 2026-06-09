import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre uma conversa no WhatsApp com o cliente, já com uma mensagem de
/// reativação pré-preenchida (o barbeiro pode editar antes de enviar).
///
/// Tenta o app nativo primeiro e cai para os links web se necessário.
Future<void> openWhatsAppReactivation(
  BuildContext context, {
  required String phone,
  required String name,
}) async {
  var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return;
  if (!digits.startsWith('55')) digits = '55$digits';

  final hour = DateTime.now().hour;
  final greet = hour < 12
      ? 'Bom dia'
      : hour < 18
      ? 'Boa tarde'
      : 'Boa noite';
  final first = name.trim().split(' ').first;
  final hi = first.isEmpty ? '$greet!' : '$greet, $first!';
  final msg = Uri.encodeComponent(
    '$hi Faz um tempinho que você não aparece aqui na barbearia. '
    'Quer agendar um horário?',
  );

  // Captura o messenger antes do gap assíncrono (lint context-sync).
  final messenger = ScaffoldMessenger.of(context);
  for (final u in [
    Uri.parse('whatsapp://send?phone=$digits&text=$msg'),
    Uri.parse('https://api.whatsapp.com/send?phone=$digits&text=$msg'),
    Uri.parse('https://wa.me/$digits?text=$msg'),
  ]) {
    try {
      if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
  }
  messenger.showSnackBar(
    const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
  );
}
