import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../widgets/action_preview.dart';

/// Lista de links de descadastro por remetente.
class UnsubscribePage extends StatefulWidget {
  const UnsubscribePage({super.key, required this.state});

  final AppState state;

  @override
  State<UnsubscribePage> createState() => _UnsubscribePageState();
}

class _UnsubscribePageState extends State<UnsubscribePage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _withoutHeader = false;
  bool _hideDone = true;
  final _scanning = <String>{};
  int _seenVersion = -1;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
    _load();
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (state.dataVersion != _seenVersion) {
      _load();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    _seenVersion = state.dataVersion;
    setState(() => _loading = true);
    try {
      final res = await state.api.get('/api/unsubscribe', {
        'withoutHeader': '$_withoutHeader',
        'includeDone': '${!_hideDone}',
      });
      _items = (res['items'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _show(e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setDone(String email, bool done) async {
    await state.api.post(
      '/api/unsubscribe/${Uri.encodeComponent(email)}/done',
      {'done': done},
    );
    await _load();
  }

  Future<void> _scan(String email) async {
    setState(() => _scanning.add(email));
    try {
      final res = await state.api.post(
        '/api/unsubscribe/${Uri.encodeComponent(email)}/scan',
      );
      if ((res['links'] as List).isEmpty) {
        _show('Nenhum link de descadastro encontrado no último e-mail.');
      }
      await _load();
    } catch (e) {
      _show(e.toString());
    }
    if (mounted) setState(() => _scanning.remove(email));
  }

  void _export(String format) => launchUrl(
    state.api.uri('/api/unsubscribe/export', {'format': format}),
    webOnlyWindowName: '_blank',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Descadastro', style: theme.textTheme.headlineSmall),
              FilterChip(
                label: const Text('Ocultar concluídos'),
                selected: _hideDone,
                onSelected: (v) {
                  _hideDone = v;
                  _load();
                },
              ),
              FilterChip(
                label: const Text('Incluir remetentes sem cabeçalho'),
                selected: _withoutHeader,
                onSelected: (v) {
                  _withoutHeader = v;
                  _load();
                },
              ),
              OutlinedButton.icon(
                onPressed: () => _export('csv'),
                icon: const Icon(Icons.download),
                label: const Text('CSV'),
              ),
              OutlinedButton.icon(
                onPressed: () => _export('md'),
                icon: const Icon(Icons.download),
                label: const Text('Markdown'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Ordenado por volume. Abra o link, confirme o descadastro na página do remetente e marque como feito.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? const Center(child: Text('Nenhum remetente para descadastrar.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _items.length,
                  itemBuilder: (context, i) => _tile(context, _items[i]),
                ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> item) {
    final email = item['email'] as String;
    final name = item['name'] as String? ?? '';
    final links = item['links'] as Map<String, dynamic>;
    final http = (links['http'] as List).cast<String>();
    final mailto = (links['mailto'] as List).cast<String>();
    final bodyLinks = (item['bodyLinks'] as List?)?.cast<String>();
    final done = item['doneMs'] != null;
    final count = item['count'] as num;
    final unread = item['unread'] as num;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          children: [
            Checkbox(
              value: done,
              onChanged: (v) => _setDone(email, v ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? email : '$name <$email>',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    '${formatCount(count)} e-mails · ${formatPercent(count == 0 ? 0 : unread / count)} não lidos · '
                    '${formatBytes(item['totalSize'] as num)} · último em ${formatDate(item['lastMs'] as num?)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (links['oneClick'] == true)
                        const Chip(
                          label: Text('1 clique'),
                          visualDensity: VisualDensity.compact,
                        ),
                      for (final link in http)
                        _linkButton(link, Icons.open_in_new, 'Abrir link'),
                      for (final link in mailto)
                        _linkButton(link, Icons.mail_outline, 'Enviar e-mail'),
                      for (final link in bodyLinks ?? const <String>[])
                        _linkButton(link, Icons.link, 'Link do corpo'),
                      if (http.isEmpty && mailto.isEmpty && bodyLinks == null)
                        OutlinedButton.icon(
                          onPressed: _scanning.contains(email)
                              ? null
                              : () => _scan(email),
                          icon: _scanning.contains(email)
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.manage_search),
                          label: const Text('Procurar no corpo'),
                        ),
                      if (bodyLinks != null &&
                          bodyLinks.isEmpty &&
                          http.isEmpty &&
                          mailto.isEmpty)
                        const Chip(
                          label: Text('Sem link — use filtro/lixeira'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mais ações',
              onSelected: (v) => previewAndRun(
                context,
                state,
                action: v,
                target: {
                  'senders': [email],
                },
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'trash',
                  child: Text('Mover todos para a lixeira…'),
                ),
                if (state.canDeletePermanently)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Apagar todos permanentemente…'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkButton(String link, IconData icon, String label) {
    return Tooltip(
      message: link,
      child: FilledButton.tonalIcon(
        onPressed: () =>
            launchUrl(Uri.parse(link), webOnlyWindowName: '_blank'),
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: link));
          _show('Link copiado.');
        },
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
