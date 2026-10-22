import 'package:flutter/material.dart';

import '../../api.dart';
import 'section_card.dart';

/// Dispara a sincronização do cache, opcionalmente filtrada por uma busca.
class SyncCard extends StatefulWidget {
  const SyncCard({super.key, required this.state, required this.neverSynced});

  final AppState state;
  final bool neverSynced;

  @override
  State<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<SyncCard> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    try {
      final res = await widget.state.api.post('/api/sync', {
        'query': _query.text,
      });
      widget.state.trackJob(res['job'] as Map<String, dynamic>);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: Icons.sync,
      title: 'Sincronizar',
      children: [
        Text(
          widget.neverSynced
              ? 'Primeiro passo: baixar os metadados (remetente, assunto, '
                    'data, tamanho) para o cache local. Caixas grandes podem '
                    'levar alguns minutos — o conteúdo dos e-mails não é '
                    'baixado.'
              : 'Busca novidades e remove do cache o que foi apagado fora do '
                    'Silver Mail.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                decoration: const InputDecoration(
                  labelText: 'Filtro opcional (sintaxe de busca do Gmail)',
                  hintText: 'ex.: newer_than:1y  — vazio = caixa inteira',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: widget.state.jobRunning ? null : _sync,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar'),
            ),
          ],
        ),
      ],
    );
  }
}
