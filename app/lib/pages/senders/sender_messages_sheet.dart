import 'package:flutter/material.dart';

import '../../format.dart';

/// Bottom sheet com as mensagens mais recentes de um remetente.
class SenderMessagesSheet extends StatelessWidget {
  const SenderMessagesSheet({
    super.key,
    required this.email,
    required this.messages,
  });

  final String email;
  final List<Map<String, dynamic>> messages;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          ListTile(
            title: Text(email, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final m in messages)
            ListTile(
              dense: true,
              leading: Icon(
                m['unread'] == true
                    ? Icons.mark_email_unread_outlined
                    : Icons.drafts_outlined,
              ),
              title: Text(
                (m['subject'] as String).isEmpty
                    ? '(sem assunto)'
                    : m['subject'] as String,
              ),
              subtitle: Text(
                '${formatDate(m['dateMs'] as num)} · '
                '${formatBytes(m['size'] as num)}',
              ),
            ),
        ],
      ),
    );
  }
}
