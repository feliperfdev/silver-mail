import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../widgets/action_preview.dart';

/// Ranking de remetentes com seleção e ações em massa.
class SendersPage extends StatefulWidget {
  const SendersPage({super.key, required this.state});

  final AppState state;

  @override
  State<SendersPage> createState() => _SendersPageState();
}

class _SendersPageState extends State<SendersPage> {
  static const _pageSize = 100;
  static const _sorts = {
    'count': 'Quantidade',
    'size': 'Espaço',
    'unread': '% não lidos',
    'last': 'Último envio',
  };

  final _items = <Map<String, dynamic>>[];
  final _selected = <String>{};
  int _total = 0;
  bool _loading = false;
  String _sort = 'count';
  bool _onlyUnsubscribe = false;
  String _search = '';
  Timer? _debounce;
  int _seenVersion = -1;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
    _reload();
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    _debounce?.cancel();
    super.dispose();
  }

  void _onState() {
    if (state.dataVersion != _seenVersion) {
      _reload();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _reload() async {
    _seenVersion = state.dataVersion;
    _items.clear();
    _selected.clear();
    await _loadMore();
  }

  Future<void> _loadMore() async {
    setState(() => _loading = true);
    try {
      final res = await state.api.get('/api/senders', {
        'sort': _sort,
        'search': _search,
        'onlyUnsubscribe': '$_onlyUnsubscribe',
        'limit': '$_pageSize',
        'offset': '${_items.length}',
      });
      _items.addAll((res['items'] as List).cast<Map<String, dynamic>>());
      _total = res['total'] as int;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _run(String action) => previewAndRun(
    context,
    state,
    action: action,
    target: {'senders': _selected.toList()},
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
              Text('Remetentes', style: theme.textTheme.headlineSmall),
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar remetente',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), () {
                      _search = v;
                      _reload();
                    });
                  },
                ),
              ),
              DropdownButton<String>(
                value: _sort,
                items: [
                  for (final e in _sorts.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text('Ordenar: ${e.value}'),
                    ),
                ],
                onChanged: (v) {
                  _sort = v!;
                  _reload();
                },
              ),
              FilterChip(
                label: const Text('Só com descadastro'),
                selected: _onlyUnsubscribe,
                onSelected: (v) {
                  _onlyUnsubscribe = v;
                  _reload();
                },
              ),
            ],
          ),
        ),
        if (_selected.isNotEmpty) _selectionBar(theme),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Text(
            'Mostrando ${formatCount(_items.length)} de ${formatCount(_total)} remetentes',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: _items.isEmpty && !_loading
              ? const Center(
                  child: Text('Nada por aqui. Já sincronizou na Visão geral?'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _items.length + 1,
                  itemBuilder: (context, i) {
                    if (i == _items.length) {
                      if (_loading) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return _items.length < _total
                          ? Center(
                              child: TextButton(
                                onPressed: _loadMore,
                                child: const Text('Carregar mais'),
                              ),
                            )
                          : const SizedBox.shrink();
                    }
                    return _senderTile(context, _items[i]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _selectionBar(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${_selected.length} selecionado(s)'),
          FilledButton.tonalIcon(
            onPressed: state.jobRunning ? null : () => _run('trash'),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Lixeira…'),
          ),
          OutlinedButton.icon(
            onPressed: state.jobRunning || !state.canDeletePermanently
                ? null
                : () => _run('delete'),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Apagar permanentemente…'),
          ),
          TextButton(
            onPressed: () => setState(_selected.clear),
            child: const Text('Limpar seleção'),
          ),
        ],
      ),
    );
  }

  Widget _senderTile(BuildContext context, Map<String, dynamic> s) {
    final email = s['email'] as String;
    final name = s['name'] as String? ?? '';
    final ratio = (s['unreadRatio'] as num?) ?? 0;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Checkbox(
          value: _selected.contains(email),
          onChanged: (v) => setState(
            () => v == true ? _selected.add(email) : _selected.remove(email),
          ),
        ),
        title: Text(
          name.isEmpty ? email : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${name.isEmpty ? '' : '$email · '}último em ${formatDate(s['lastMs'] as num?)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Wrap(
          spacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (s['hasUnsubscribe'] == true)
              const Tooltip(
                message: 'Tem link de descadastro',
                child: Icon(Icons.unsubscribe_outlined, size: 20),
              ),
            _metric('${formatCount(s['count'] as num)} e-mails', null),
            _metric(formatBytes(s['totalSize'] as num), null),
            _metric(
              '${formatPercent(ratio)} não lidos',
              ratio >= 0.9 ? scheme.error : null,
            ),
          ],
        ),
        onTap: () => _showMessages(context, email),
      ),
    );
  }

  Widget _metric(String text, Color? color) => SizedBox(
    width: 110,
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(color: color),
    ),
  );

  Future<void> _showMessages(BuildContext context, String email) async {
    final res = await state.api.get(
      '/api/senders/${Uri.encodeComponent(email)}/messages',
    );
    if (!context.mounted) return;
    final items = (res['items'] as List).cast<Map<String, dynamic>>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            ListTile(
              title: Text(
                email,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final m in items)
              ListTile(
                dense: true,
                leading: Icon(
                  m['unread'] == true
                      ? Icons.mark_email_unread_outlined
                      : Icons.drafts_outlined,
                ),
                title: Text(
                  (m['subject'] as String).isEmpty
                      ? '(sem assunto)'
                      : m['subject'] as String,
                ),
                subtitle: Text(
                  '${formatDate(m['dateMs'] as num)} · ${formatBytes(m['size'] as num)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
