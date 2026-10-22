String formatBytes(num? bytes) {
  final b = (bytes ?? 0).toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = b;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[unit]}';
}

String formatCount(num? n) {
  final s = (n ?? 0).toInt().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}

String formatDate(num? ms) {
  if (ms == null || ms == 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String formatDateTime(num? ms) {
  if (ms == null || ms == 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  String two(int v) => v.toString().padLeft(2, '0');
  return '${formatDate(ms)} ${two(d.hour)}:${two(d.minute)}';
}

String formatPercent(num? ratio) => '${((ratio ?? 0) * 100).round()}%';
