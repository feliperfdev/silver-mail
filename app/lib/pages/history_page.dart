import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';

/// Ações executadas, com opção de desfazer o que foi para a lixeira.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.state});

  final AppState state;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  int _seenVersion = -1;

  AppState get state => widget.state;

  static const _kinds = {
    'trash': ('Lixeira', Icons.delete_outline),
    'delete': ('Exclusão permanente', Icons.delete_forever),
  };

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
    try {
      final res = await state.api.get('/api/actions/history');
      _items = (res['items'] as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _undo(int id) async {
    try {
      final res = await state.api.post('/api/actions/$id/undo');
      state.trackJob(res['job'] as Map<String, dynamic>);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Histórico', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_items.isEmpty)
          const Text('Nenhuma ação executada ainda.')
        else
          for (final a in _items)
            Card(
              child: ListTile(
                leading: Icon(_kinds[a['kind']]?.$2 ?? Icons.history),
                title: Text(
                  '${_kinds[a['kind']]?.$1 ?? a['kind']} · ${a['description']}',
                ),
                subtitle: Text(
                  '${formatDateTime(a['createdMs'] as num)} · ${formatCount(a['count'] as num)} mensagens · '
                  '${formatBytes(a['totalSize'] as num)}'
                  '${a['undoneMs'] != null ? ' · desfeita em ${formatDateTime(a['undoneMs'] as num)}' : ''}',
                ),
                trailing: a['undoable'] == true
                    ? TextButton.icon(
                        onPressed: state.jobRunning
                            ? null
                            : () => _undo(a['id'] as int),
                        icon: const Icon(Icons.undo),
                        label: const Text('Desfazer'),
                      )
                    : null,
              ),
            ),
      ],
    );
  }
}
