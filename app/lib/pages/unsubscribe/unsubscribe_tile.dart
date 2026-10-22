import 'package:flutter/material.dart';

import '../../format.dart';
import 'unsubscribe_link_button.dart';

/// Card de um remetente com seus links de descadastro
/// (item de `/api/unsubscribe`).
class UnsubscribeTile extends StatelessWidget {
  const UnsubscribeTile({
    super.key,
    required this.item,
    required this.scanning,
    required this.canDeletePermanently,
    required this.onDoneChanged,
    required this.onScan,
    required this.onBulkAction,
  });

  final Map<String, dynamic> item;

  /// Busca de links no corpo em andamento para este remetente.
  final bool scanning;
  final bool canDeletePermanently;
  final ValueChanged<bool> onDoneChanged;
  final VoidCallback onScan;

  /// Recebe `'trash'` ou `'delete'`.
  final ValueChanged<String> onBulkAction;

  @override
  Widget build(BuildContext context) {
    final email = item['email'] as String;
    final name = item['name'] as String? ?? '';
    final links = item['links'] as Map<String, dynamic>;
    final http = (links['http'] as List).cast<String>();
    final mailto = (links['mailto'] as List).cast<String>();
    final bodyLinks = (item['bodyLinks'] as List?)?.cast<String>();
    final done = item['doneMs'] != null;
    final count = item['count'] as num;
    final unread = item['unread'] as num;
    final noHeader = http.isEmpty && mailto.isEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          children: [
            Checkbox(value: done, onChanged: (v) => onDoneChanged(v ?? false)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? email : '$name <$email>',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    '${formatCount(count)} e-mails · '
                    '${formatPercent(count == 0 ? 0 : unread / count)} não '
                    'lidos · ${formatBytes(item['totalSize'] as num)} · '
                    'último em ${formatDate(item['lastMs'] as num?)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (links['oneClick'] == true)
                        const Chip(
                          label: Text('1 clique'),
                          visualDensity: VisualDensity.compact,
                        ),
                      for (final link in http)
                        UnsubscribeLinkButton(
                          link: link,
                          icon: Icons.open_in_new,
                          label: 'Abrir link',
                        ),
                      for (final link in mailto)
                        UnsubscribeLinkButton(
                          link: link,
                          icon: Icons.mail_outline,
                          label: 'Enviar e-mail',
                        ),
                      for (final link in bodyLinks ?? const <String>[])
                        UnsubscribeLinkButton(
                          link: link,
                          icon: Icons.link,
                          label: 'Link do corpo',
                        ),
                      if (noHeader && bodyLinks == null)
                        OutlinedButton.icon(
                          onPressed: scanning ? null : onScan,
                          icon: scanning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.manage_search),
                          label: const Text('Procurar no corpo'),
                        ),
                      if (noHeader && bodyLinks != null && bodyLinks.isEmpty)
                        const Chip(
                          label: Text('Sem link — use filtro/lixeira'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mais ações',
              onSelected: onBulkAction,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'trash',
                  child: Text('Mover todos para a lixeira…'),
                ),
                if (canDeletePermanently)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Apagar todos permanentemente…'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
