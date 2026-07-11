import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:barbearia/repositories/clients_repository.dart';
import 'package:barbearia/services/whatsapp_service.dart';
import 'package:barbearia/utils/slot_logic.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dashboard de clientes: nome, telefone, nº visitas, última visita.
class ClientsAdminScreen extends StatefulWidget {
  const ClientsAdminScreen({super.key});

  @override
  State<ClientsAdminScreen> createState() => _ClientsAdminScreenState();
}

class _ClientsAdminScreenState extends State<ClientsAdminScreen> {
  static const _bg = Color(0xFF080808);
  static const _card = Color(0xFF111111);
  static const _border = Color(0xFF222222);
  static const _gold = Color(0xFFF5C200);
  static const _text = Color(0xFFF0EDE8);
  static const _muted = Color(0xFF6B7280);

  final _repo = ClientsRepository();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<ClientSummary> _all = const [];
  List<ClientSummary> _filtered = const [];
  _SortMode _sort = _SortMode.lastVisit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.fetchAll();
      if (!mounted) return;
      setState(() {
        _all = list;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    var list = List<ClientSummary>.from(_all);
    if (q.isNotEmpty) {
      final qDigits = SlotLogic.normalizePhone(q);
      list = list.where((c) {
        return c.name.toLowerCase().contains(q) ||
            SlotLogic.normalizePhone(c.phone).contains(qDigits);
      }).toList();
    }
    switch (_sort) {
      case _SortMode.lastVisit:
        list.sort((a, b) {
          final la = a.lastVisit ?? DateTime.fromMillisecondsSinceEpoch(0);
          final lb = b.lastVisit ?? DateTime.fromMillisecondsSinceEpoch(0);
          return lb.compareTo(la);
        });
      case _SortMode.visits:
        list.sort((a, b) => b.visitCount.compareTo(a.visitCount));
      case _SortMode.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }
    _filtered = list;
  }

  String _fmtPhone(String raw) {
    final d = SlotLogic.normalizePhone(raw);
    if (d.length == 11) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
    }
    if (d.length == 10) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }
    return raw;
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('dd/MM/yyyy').format(d);
  }

  Future<void> _openWhatsApp(ClientSummary c) async {
    final digits = SlotLogic.normalizePhone(c.phone);
    final full = digits.startsWith('55') ? digits : '55$digits';
    final uri = Uri.parse('https://wa.me/$full');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sendTemplate(ClientSummary c) async {
    final config = await WhatsappService.loadConfig();
    if (!config.enabled || !config.isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp não configurado.')),
      );
      return;
    }
    final msg =
        'Olá ${c.name}! Sentimos sua falta na Toni Dinis Barbearia 💈\n'
        'Quer remarcar? É só responder esta mensagem.';
    final res = await WhatsappService.sendMessage(
      phone: c.phone,
      message: msg,
      config: config,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.ok ? 'Mensagem enviada!' : (res.error ?? 'Falha')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _text,
        title: const Text('Clientes'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: _text),
              decoration: InputDecoration(
                hintText: 'Buscar nome ou telefone…',
                hintStyle: const TextStyle(color: _muted),
                prefixIcon: const Icon(Icons.search, color: _muted),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _gold),
                ),
              ),
              onChanged: (_) => setState(_applyFilter),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  _loading ? '…' : '${_filtered.length} cliente(s)',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const Spacer(),
                DropdownButtonHideUnderline(
                  child: DropdownButton<_SortMode>(
                    value: _sort,
                    dropdownColor: _card,
                    style: const TextStyle(color: _text, fontSize: 13),
                    items: const [
                      DropdownMenuItem(
                        value: _SortMode.lastVisit,
                        child: Text('Última visita'),
                      ),
                      DropdownMenuItem(
                        value: _SortMode.visits,
                        child: Text('Mais visitas'),
                      ),
                      DropdownMenuItem(
                        value: _SortMode.name,
                        child: Text('Nome'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _sort = v;
                        _applyFilter();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erro: $_error', style: const TextStyle(color: _muted)),
        ),
      );
    }
    if (_filtered.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum cliente encontrado.',
          style: TextStyle(color: _muted),
        ),
      );
    }
    return RefreshIndicator(
      color: _gold,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final c = _filtered[i];
          return Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _gold.withValues(alpha: 0.15),
                  child: Text(
                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (c.isPlanClient)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Mensalista',
                                style: TextStyle(
                                  color: _gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmtPhone(c.phone),
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${c.visitCount} visita(s) · última ${_fmtDate(c.lastVisit)}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'WhatsApp',
                  onPressed: () => _openWhatsApp(c),
                  icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                ),
                IconButton(
                  tooltip: 'Reativar',
                  onPressed: () => _sendTemplate(c),
                  icon: const Icon(Icons.campaign_outlined, color: _gold),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _SortMode { lastVisit, visits, name }
