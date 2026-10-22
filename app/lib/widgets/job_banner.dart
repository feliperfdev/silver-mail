import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';

/// Faixa no topo mostrando a tarefa atual ou o resultado da última.
class JobBanner extends StatelessWidget {
  const JobBanner({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final job = state.job;
    if (job == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final running = job['running'] == true;
    final error = job['error'] as String?;
    final total = (job['total'] as num?) ?? 0;
    final done = (job['done'] as num?) ?? 0;

    final Color background;
    final IconData icon;
    if (error != null) {
      background = scheme.errorContainer;
      icon = Icons.error_outline;
    } else if (running) {
      background = scheme.secondaryContainer;
      icon = Icons.sync;
    } else {
      background = scheme.tertiaryContainer;
      icon = Icons.check_circle_outline;
    }

    final progress = total > 0
        ? '${formatCount(done)} de ${formatCount(total)}'
        : formatCount(done);
    final detail =
        error ?? '${job['phase']}${running || total > 0 ? ' — $progress' : ''}';

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${job['description']}  ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: detail),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (running) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: total > 0 ? done / total : null),
            ],
          ],
        ),
      ),
    );
  }
}
