import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../format.dart';
import '../../widgets/action_preview/action_preview.dart';
import 'selection_bar.dart';
import 'sender_messages_sheet.dart';
import 'sender_tile.dart';

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

  Future<void> _showMessages(String email) async {
    final res = await state.api.get(
      '/api/senders/${Uri.encodeComponent(email)}/messages',
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SenderMessagesSheet(
        email: email,
        messages: (res['items'] as List).cast<Map<String, dynamic>>(),
      ),
    );
  }

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
        if (_selected.isNotEmpty)
          SelectionBar(
            count: _selected.length,
            onTrash: state.jobRunning ? null : () => _run('trash'),
            onDelete: state.jobRunning || !state.canDeletePermanently
                ? null
                : () => _run('delete'),
            onClear: () => setState(_selected.clear),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Text(
            'Mostrando ${formatCount(_items.length)} de '
            '${formatCount(_total)} remetentes',
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
                    final email = _items[i]['email'] as String;
                    return SenderTile(
                      key: ValueKey(email),
                      sender: _items[i],
                      selected: _selected.contains(email),
                      onSelectedChanged: (v) => setState(
                        () =>
                            v ? _selected.add(email) : _selected.remove(email),
                      ),
                      onTap: () => _showMessages(email),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
