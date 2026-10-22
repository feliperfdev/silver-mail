import 'package:flutter/material.dart';

/// Diálogo de espera enquanto o servidor monta a prévia.
///
/// Fecha sozinho: devolve a prévia via `Navigator.pop` ou, em caso de erro,
/// fecha sem resultado e mostra o erro num SnackBar.
class LoadingPreviewDialog extends StatefulWidget {
  const LoadingPreviewDialog({super.key, required this.future});

  final Future<Map<String, dynamic>> future;

  @override
  State<LoadingPreviewDialog> createState() => _LoadingPreviewDialogState();
}

class _LoadingPreviewDialogState extends State<LoadingPreviewDialog> {
  @override
  void initState() {
    super.initState();
    _await();
  }

  Future<void> _await() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final preview = await widget.future;
      if (mounted) navigator.pop(preview);
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Consultando o Gmail para montar a prévia…')),
        ],
      ),
    );
  }
}
