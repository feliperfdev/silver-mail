import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre o link em nova aba; pressionar e segurar copia o link.
class UnsubscribeLinkButton extends StatelessWidget {
  const UnsubscribeLinkButton({
    super.key,
    required this.link,
    required this.icon,
    required this.label,
  });

  final String link;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: link,
      child: FilledButton.tonalIcon(
        onPressed: () =>
            launchUrl(Uri.parse(link), webOnlyWindowName: '_blank'),
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: link));
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Link copiado.')));
        },
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
