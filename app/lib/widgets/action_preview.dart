import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';

/// Gera a prévia no servidor, mostra o que será afetado e só executa
/// depois da confirmação.
///
/// [target] é `{'senders': [...]}` ou `{'query': '...'}`.
Future<void> previewAndRun(
  BuildContext context,
  AppState state, {
  required String action,
  required Map<String, Object?> target,
}) async {
  if (state.jobRunning) {
    _snack(context, 'Aguarde a tarefa atual terminar.');
    return;
  }

  Map<String, dynamic> preview;
  try {
    preview =
        await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _LoadingPreview(
            state.api.post('/api/actions/preview', {
              'action': action,
              ...target,
            }),
          ),
        ) ??
        {};
  } catch (e) {
    if (context.mounted) _snack(context, e.toString());
    return;
  }
  if (preview.isEmpty || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _PreviewDialog(preview: preview),
  );
  if (confirmed != true) return;

  try {
    final res = await state.api.post('/api/actions/execute', {
      'token': preview['token'],
    });
    state.trackJob(res['job'] as Map<String, dynamic>);
  } catch (e) {
    if (context.mounted) _snack(context, e.toString());
  }
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class _LoadingPreview extends StatelessWidget {
  const _LoadingPreview(this.future);

  final Future<Map<String, dynamic>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            if (snap.hasError) {
              Navigator.of(context).pop();
              _snack(context, snap.error.toString());
            } else {
              Navigator.of(context).pop(snap.data);
            }
          });
        }
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text('Consultando o Gmail para montar a prévia…'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({required this.preview});

  final Map<String, dynamic> preview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              '${formatCount(count)} mensagens · ${formatBytes(preview['totalSize'] as num)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (isDelete) ...[
              const SizedBox(height: 8),
              Text(
                'Esta ação NÃO pode ser desfeita — as mensagens não passam pela lixeira.',
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Você pode desfazer pelo Histórico enquanto estiverem na lixeira (30 dias).',
                ),
              ),
            if (sample.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Exemplos', style: Theme.of(context).textTheme.labelLarge),
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
                            '${m['fromEmail']} · ${formatDate(m['dateMs'] as num)}',
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
