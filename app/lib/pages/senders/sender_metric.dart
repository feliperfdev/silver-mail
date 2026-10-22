import 'package:flutter/material.dart';

/// Coluna numérica de largura fixa na linha de um remetente.
class SenderMetric extends StatelessWidget {
  const SenderMetric({super.key, required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(color: color),
      ),
    );
  }
}
