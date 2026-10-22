import 'package:flutter/material.dart';

import '../../format.dart';
import 'sender_metric.dart';

/// Linha do ranking de remetentes (item de `/api/senders`).
class SenderTile extends StatelessWidget {
  const SenderTile({
    super.key,
    required this.sender,
    required this.selected,
    required this.onSelectedChanged,
    required this.onTap,
  });

  final Map<String, dynamic> sender;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final email = sender['email'] as String;
    final name = sender['name'] as String? ?? '';
    final ratio = (sender['unreadRatio'] as num?) ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Checkbox(
          value: selected,
          onChanged: (v) => onSelectedChanged(v ?? false),
        ),
        title: Text(
          name.isEmpty ? email : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${name.isEmpty ? '' : '$email · '}'
          'último em ${formatDate(sender['lastMs'] as num?)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Wrap(
          spacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (sender['hasUnsubscribe'] == true)
              const Tooltip(
                message: 'Tem link de descadastro',
                child: Icon(Icons.unsubscribe_outlined, size: 20),
              ),
            SenderMetric(
              text: '${formatCount(sender['count'] as num)} e-mails',
            ),
            SenderMetric(text: formatBytes(sender['totalSize'] as num)),
            SenderMetric(
              text: '${formatPercent(ratio)} não lidos',
              color: ratio >= 0.9 ? scheme.error : null,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
