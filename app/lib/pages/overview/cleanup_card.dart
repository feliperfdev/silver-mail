import 'package:flutter/material.dart';

import '../../api.dart';
import '../../widgets/action_preview/action_preview.dart';
import 'section_card.dart';

/// Lixeira ou exclusão em massa a partir de uma busca do Gmail.
class CleanupCard extends StatefulWidget {
  const CleanupCard({super.key, required this.state});

  final AppState state;

  @override
  State<CleanupCard> createState() => _CleanupCardState();
}

class _CleanupCardState extends State<CleanupCard> {
  static const _presets = {
    'Promoções > 1 ano': 'category:promotions older_than:1y',
    'Redes sociais > 6 meses': 'category:social older_than:6m',
    'Maiores que 10 MB': 'larger:10M',
    'Não lidos > 2 anos': 'is:unread older_than:2y',
  };

  final _query = TextEditingController();

  AppState get state => widget.state;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _clean(String action) {
    final q = _query.text.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Digite uma busca.')));
      return;
    }
    previewAndRun(context, state, action: action, target: {'query': q});
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: Icons.cleaning_services_outlined,
      title: 'Limpeza por busca',
      children: [
        const Text(
          'Use qualquer busca do Gmail. Você sempre vê uma prévia antes de '
          'confirmar.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in _presets.entries)
              ActionChip(
                label: Text(e.key),
                onPressed: () => _query.text = e.value,
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _query,
          decoration: const InputDecoration(
            labelText: 'Busca',
            hintText: 'ex.: from:loja.com older_than:6m',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.tonalIcon(
              onPressed: state.jobRunning ? null : () => _clean('trash'),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Mover para a lixeira…'),
            ),
            OutlinedButton.icon(
              onPressed: state.jobRunning || !state.canDeletePermanently
                  ? null
                  : () => _clean('delete'),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Apagar permanentemente…'),
            ),
          ],
        ),
      ],
    );
  }
}
