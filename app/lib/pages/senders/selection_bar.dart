import 'package:flutter/material.dart';

/// Barra de ações exibida quando há remetentes selecionados.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.onTrash,
    required this.onDelete,
    required this.onClear,
  });

  final int count;

  /// `null` desabilita o botão (ex.: tarefa em andamento).
  final VoidCallback? onTrash;
  final VoidCallback? onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$count selecionado(s)'),
          FilledButton.tonalIcon(
            onPressed: onTrash,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Lixeira…'),
          ),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Apagar permanentemente…'),
          ),
          TextButton(onPressed: onClear, child: const Text('Limpar seleção')),
        ],
      ),
    );
  }
}
