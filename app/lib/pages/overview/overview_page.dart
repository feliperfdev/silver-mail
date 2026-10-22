import 'package:flutter/material.dart';

import '../../api.dart';
import 'account_card.dart';
import 'cleanup_card.dart';
import 'stats_grid.dart';
import 'sync_card.dart';

/// Conta, sincronização, números gerais e limpeza por busca.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.state});

  final AppState state;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  Map<String, dynamic>? _stats;
  int _seenVersion = -1;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
    _loadStats();
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (state.dataVersion != _seenVersion) _loadStats();
    if (mounted) setState(() {});
  }

  Future<void> _loadStats() async {
    _seenVersion = state.dataVersion;
    try {
      final stats = await state.api.get('/api/stats');
      if (mounted) setState(() => _stats = stats);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Visão geral', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        AccountCard(state: state),
        if (state.authenticated) ...[
          if (stats != null) ...[
            const SizedBox(height: 16),
            StatsGrid(stats: stats),
          ],
          const SizedBox(height: 16),
          SyncCard(state: state, neverSynced: stats?['lastSyncMs'] == null),
          const SizedBox(height: 16),
          CleanupCard(state: state),
        ],
      ],
    );
  }
}
