import 'package:flutter/material.dart';

import '../../format.dart';
import 'stat_tile.dart';

/// Números gerais do cache local (resposta de `/api/stats`).
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        StatTile(
          label: 'Mensagens no cache',
          value: formatCount(s['totalMessages'] as num),
          icon: Icons.mail_outline,
        ),
        StatTile(
          label: 'Espaço ocupado',
          value: formatBytes(s['totalSize'] as num),
          icon: Icons.storage,
        ),
        StatTile(
          label: 'Não lidas',
          value: formatCount(s['unread'] as num),
          icon: Icons.mark_email_unread_outlined,
        ),
        StatTile(
          label: 'Remetentes',
          value: formatCount(s['senders'] as num),
          icon: Icons.people_outline,
        ),
        StatTile(
          label: 'Com link de descadastro',
          value: formatCount(s['sendersWithUnsubscribe'] as num),
          icon: Icons.unsubscribe_outlined,
        ),
        StatTile(
          label: 'Última sincronização',
          value: formatDateTime(s['lastSyncMs'] as num?),
          icon: Icons.schedule,
        ),
      ],
    );
  }
}
