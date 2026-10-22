import 'package:flutter/material.dart';

import '../../api.dart';
import 'loading_preview_dialog.dart';
import 'preview_dialog.dart';

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
  final messenger = ScaffoldMessenger.of(context);
  void snack(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));

  if (state.jobRunning) {
    snack('Aguarde a tarefa atual terminar.');
    return;
  }

  final preview = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LoadingPreviewDialog(
      future: state.api.post('/api/actions/preview', {
        'action': action,
        ...target,
      }),
    ),
  );
  if (preview == null || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => PreviewDialog(preview: preview),
  );
  if (confirmed != true) return;

  try {
    final res = await state.api.post('/api/actions/execute', {
      'token': preview['token'],
    });
    state.trackJob(res['job'] as Map<String, dynamic>);
  } catch (e) {
    snack(e.toString());
  }
}
