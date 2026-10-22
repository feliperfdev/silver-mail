import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api.dart';
import '../../widgets/action_preview/action_preview.dart';
import 'unsubscribe_tile.dart';

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
            'Ordenado por volume. Abra o link, confirme o descadastro na '
            'página do remetente e marque como feito.',
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
                  itemBuilder: (context, i) {
                    final email = _items[i]['email'] as String;
                    return UnsubscribeTile(
                      key: ValueKey(email),
                      item: _items[i],
                      scanning: _scanning.contains(email),
                      canDeletePermanently: state.canDeletePermanently,
                      onDoneChanged: (done) => _setDone(email, done),
                      onScan: () => _scan(email),
                      onBulkAction: (action) => previewAndRun(
                        context,
                        state,
                        action: action,
                        target: {
                          'senders': [email],
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
