import 'package:flutter/material.dart';

import '../../format.dart';

/// Mostra o que uma ação em massa vai afetar e pede confirmação.
/// Fecha com `true` quando o usuário confirma.
class PreviewDialog extends StatelessWidget {
  const PreviewDialog({super.key, required this.preview});

  final Map<String, dynamic> preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = preview['count'] as int;
    final isDelete = preview['action'] == 'delete';
    final sample = (preview['sample'] as List).cast<Map<String, dynamic>>();

    return AlertDialog(
      icon: Icon(
        isDelete ? Icons.delete_forever : Icons.delete_outline,
        color: isDelete ? scheme.error : null,
      ),
      title: Text(
        isDelete ? 'Apagar permanentemente?' : 'Mover para a lixeira?',
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview['description'] as String),
            const SizedBox(height: 8),
            Text(
              '${formatCount(count)} mensagens · '
              '${formatBytes(preview['totalSize'] as num)}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (isDelete)
              Text(
                'Esta ação NÃO pode ser desfeita — as mensagens não passam '
                'pela lixeira.',
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              const Text(
                'Você pode desfazer pelo Histórico enquanto estiverem na '
                'lixeira (30 dias).',
              ),
            if (sample.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Exemplos', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in sample)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            (m['subject'] as String).isEmpty
                                ? '(sem assunto)'
                                : m['subject'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${m['fromEmail']} · '
                            '${formatDate(m['dateMs'] as num)}',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: isDelete
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: count == 0 ? null : () => Navigator.pop(context, true),
          child: Text(
            isDelete
                ? 'Apagar ${formatCount(count)}'
                : 'Mover ${formatCount(count)}',
          ),
        ),
      ],
    );
  }
}
