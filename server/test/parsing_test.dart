import 'package:silver_mail_server/silver_mail_server.dart';
import 'package:test/test.dart';

void main() {
  group('parseFrom', () {
    test('nome entre aspas', () {
      final s = parseFrom('"Loja X" <News@LojaX.com>');
      expect(s.email, 'news@lojax.com');
      expect(s.name, 'Loja X');
    });

    test('nome sem aspas', () {
      final s = parseFrom('Loja X <news@lojax.com>');
      expect(s.email, 'news@lojax.com');
      expect(s.name, 'Loja X');
    });

    test('só o endereço', () {
      final s = parseFrom('news@lojax.com');
      expect(s.email, 'news@lojax.com');
      expect(s.name, '');
    });

    test('vazio', () => expect(parseFrom(null).email, ''));
  });

  group('parseListUnsubscribe', () {
    test('http e mailto com one-click', () {
      final l = parseListUnsubscribe(
        '<mailto:unsub@x.com?subject=unsubscribe>, <https://x.com/u?id=1>',
        'List-Unsubscribe=One-Click',
      );
      expect(l.http, ['https://x.com/u?id=1']);
      expect(l.mailto, ['mailto:unsub@x.com?subject=unsubscribe']);
      expect(l.oneClick, isTrue);
    });

    test('sem cabeçalho Post não é one-click', () {
      final l = parseListUnsubscribe('<https://x.com/u>');
      expect(l.oneClick, isFalse);
    });

    test('quebra de linha dentro do link', () {
      final l = parseListUnsubscribe('<https://x.com/\r\n u?a=1>');
      expect(l.http, ['https://x.com/u?a=1']);
    });

    test('nulo', () => expect(parseListUnsubscribe(null).isEmpty, isTrue));
  });

  group('findUnsubscribeLinksInBody', () {
    test('âncora com texto em português', () {
      final links = findUnsubscribeLinksInBody(
        html:
            '<p>Oi</p><a href="https://x.com/home">Site</a>'
            '<a href="https://x.com/out?a=1&amp;b=2"><span>Descadastre-se</span></a>',
      );
      expect(links, ['https://x.com/out?a=1&b=2']);
    });

    test('palavra-chave na URL', () {
      final links = findUnsubscribeLinksInBody(
        html: '<a href="https://x.com/unsubscribe/abc">clique aqui</a>',
      );
      expect(links, ['https://x.com/unsubscribe/abc']);
    });

    test('texto puro com link na linha seguinte', () {
      final links = findUnsubscribeLinksInBody(
        text:
            'Para cancelar a inscrição acesse:\nhttps://x.com/q?id=9\n'
            'Visite https://x.com/loja',
      );
      expect(links, ['https://x.com/q?id=9']);
    });

    test('ignora links comuns', () {
      final links = findUnsubscribeLinksInBody(
        html: '<a href="https://x.com/promo">Ver ofertas</a>',
      );
      expect(links, isEmpty);
    });
  });
}
