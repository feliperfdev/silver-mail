import 'package:silver_mail_server/silver_mail_server.dart';
import 'package:test/test.dart';

CachedMessage _msg(
  String id,
  String from, {
  int size = 100,
  bool unread = false,
  int date = 0,
  String? unsub,
}) => CachedMessage(
  id: id,
  threadId: id,
  fromEmail: from,
  fromName: from.split('@').first,
  subject: 'Assunto $id',
  dateMs: date,
  size: size,
  unread: unread,
  labels: const ['INBOX'],
  listUnsubscribe: unsub,
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemory()
      ..upsertMessages([
        _msg(
          '1',
          'a@x.com',
          unread: true,
          date: 10,
          unsub: '<https://x.com/u>',
        ),
        _msg('2', 'a@x.com', unread: true, date: 20),
        _msg('3', 'a@x.com', unread: false, date: 30, size: 500),
        _msg('4', 'b@y.com', unread: false, date: 40, size: 1000),
      ]);
  });

  tearDown(() => db.close());

  test('agrupa remetentes e ordena por quantidade', () {
    final result = db.senders();
    final items = result['items'] as List;
    expect(result['total'], 2);
    expect((items.first as Map)['email'], 'a@x.com');
    expect((items.first as Map)['count'], 3);
    expect((items.first as Map)['unread'], 2);
    expect((items.first as Map)['hasUnsubscribe'], isTrue);
  });

  test('ordena por tamanho', () {
    final items = db.senders(sort: 'size')['items'] as List;
    expect((items.first as Map)['email'], 'b@y.com');
  });

  test('mensagens na lixeira saem das estatísticas', () {
    db.markTrashed(['4'], trashed: true);
    expect(db.stats()['totalMessages'], 3);
    db.markTrashed(['4'], trashed: false);
    expect(db.stats()['totalMessages'], 4);
  });

  test('candidatos a descadastro usam a mensagem com cabeçalho', () {
    final items = db.unsubscribeCandidates();
    expect(items, hasLength(1));
    expect(items.first['listUnsubscribe'], '<https://x.com/u>');
    expect(items.first['count'], 3);
  });

  test('pruneMissing remove o que sumiu da caixa', () {
    expect(db.pruneMissing({'1', '2'}), 2);
    expect(db.knownMessageIds(), {'1', '2'});
  });

  test('histórico e desfazer', () {
    final id = db.recordAction(
      kind: 'trash',
      description: 'teste',
      ids: ['1', '2'],
      totalSize: 200,
    );
    expect(db.history().first['undoable'], isTrue);
    db.markActionUndone(id);
    expect(db.action(id)!.undone, isTrue);
    expect(db.history().first['undoable'], isFalse);
  });
}
