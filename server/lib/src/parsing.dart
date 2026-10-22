/// Funções puras de parsing de cabeçalhos e corpos de e-mail.
library;

class Sender {
  const Sender(this.email, this.name);

  final String email;
  final String name;
}

final _angleAddress = RegExp(r'<([^<>\s]+@[^<>\s]+)>');
final _bareAddress = RegExp(r'([A-Za-z0-9._%+\-=]+@[A-Za-z0-9.\-]+)');

/// Extrai e-mail e nome de um cabeçalho `From`.
///
/// Exemplos aceitos: `"Loja" <news@loja.com>`, `Loja <news@loja.com>`,
/// `news@loja.com`.
Sender parseFrom(String? header) {
  if (header == null || header.trim().isEmpty) return const Sender('', '');
  final value = header.trim();
  final angle = _angleAddress.firstMatch(value);
  if (angle != null) {
    final email = angle.group(1)!.toLowerCase();
    var name = value.substring(0, angle.start).trim();
    if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
      name = name.substring(1, name.length - 1);
    }
    return Sender(email, name.replaceAll(r'\"', '"').trim());
  }
  final bare = _bareAddress.firstMatch(value);
  if (bare != null) return Sender(bare.group(1)!.toLowerCase(), '');
  return Sender(value.toLowerCase(), '');
}

class UnsubscribeLinks {
  const UnsubscribeLinks({
    this.http = const [],
    this.mailto = const [],
    this.oneClick = false,
  });

  final List<String> http;
  final List<String> mailto;

  /// O remetente suporta descadastro com um clique (RFC 8058).
  final bool oneClick;

  bool get isEmpty => http.isEmpty && mailto.isEmpty;

  Map<String, Object> toJson() => {
    'http': http,
    'mailto': mailto,
    'oneClick': oneClick,
  };
}

final _bracketed = RegExp(r'<([^>]+)>');

/// Interpreta os cabeçalhos `List-Unsubscribe` e `List-Unsubscribe-Post`
/// (RFC 2369 e RFC 8058).
UnsubscribeLinks parseListUnsubscribe(String? header, [String? postHeader]) {
  if (header == null || header.trim().isEmpty) return const UnsubscribeLinks();
  final http = <String>[];
  final mailto = <String>[];
  for (final match in _bracketed.allMatches(header)) {
    final link = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
    final lower = link.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      http.add(link);
    } else if (lower.startsWith('mailto:')) {
      mailto.add(link);
    }
  }
  final oneClick =
      http.any((l) => l.toLowerCase().startsWith('https://')) &&
      (postHeader ?? '').toLowerCase().contains('list-unsubscribe=one-click');
  return UnsubscribeLinks(http: http, mailto: mailto, oneClick: oneClick);
}

final _keywords = RegExp(
  r'unsubscribe|unsub|opt[\s\-_]?out|descadastr|desinscrever|'
  r'cancelar\s+(a\s+)?(sua\s+)?inscri|cancelar\s+(o\s+)?recebimento|'
  r'remover\s+(da|minha|meu)|sair\s+da\s+lista|n[aã]o\s+quero\s+(mais\s+)?receber|'
  r'darse\s+de\s+baja|abmelden',
  caseSensitive: false,
);

final _anchor = RegExp(
  r'''<a\b[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>''',
  caseSensitive: false,
  dotAll: true,
);
final _tag = RegExp(r'<[^>]+>');
final _url = RegExp(r'''https?://[^\s<>"')\]]+''', caseSensitive: false);

/// Procura links de descadastro no corpo do e-mail (fallback quando não há
/// cabeçalho `List-Unsubscribe`).
List<String> findUnsubscribeLinksInBody({String? html, String? text}) {
  final found = <String>{};
  if (html != null) {
    for (final m in _anchor.allMatches(html)) {
      final href = _decodeEntities(m.group(1)!.trim());
      final label = _decodeEntities(m.group(2)!.replaceAll(_tag, ' '));
      if (!href.toLowerCase().startsWith('http')) continue;
      if (_keywords.hasMatch(label) || _keywords.hasMatch(href)) {
        found.add(href);
      }
    }
  }
  if (text != null) {
    final lines = text.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      // A URL costuma vir na mesma linha da palavra-chave ou na seguinte.
      final context = [if (i > 0) lines[i - 1], lines[i]].join(' ');
      for (final m in _url.allMatches(lines[i])) {
        final url = m.group(0)!;
        if (_keywords.hasMatch(url) || _keywords.hasMatch(context)) {
          found.add(url);
        }
      }
    }
  }
  return found.toList();
}

String _decodeEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#38;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ');
