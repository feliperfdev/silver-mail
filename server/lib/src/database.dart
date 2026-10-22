import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// Metadados de uma mensagem guardados no cache local.
class CachedMessage {
  const CachedMessage({
    required this.id,
    required this.threadId,
    required this.fromEmail,
    required this.fromName,
    required this.subject,
    required this.dateMs,
    required this.size,
    required this.unread,
    required this.labels,
    this.listUnsubscribe,
    this.listUnsubscribePost,
  });

  final String id;
  final String threadId;
  final String fromEmail;
  final String fromName;
  final String subject;
  final int dateMs;
  final int size;
  final bool unread;
  final List<String> labels;
  final String? listUnsubscribe;
  final String? listUnsubscribePost;
}

/// Camada de acesso ao SQLite: cache de mensagens, histórico de ações e
/// status de descadastro.
class AppDatabase {
  AppDatabase(String path) : _db = sqlite3.open(path) {
    _migrate();
  }

  AppDatabase.inMemory() : _db = sqlite3.openInMemory() {
    _migrate();
  }

  final Database _db;

  void _migrate() {
    _db.execute('''
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        from_email TEXT NOT NULL,
        from_name TEXT NOT NULL,
        subject TEXT NOT NULL,
        date_ms INTEGER NOT NULL,
        size INTEGER NOT NULL,
        unread INTEGER NOT NULL,
        labels TEXT NOT NULL,
        list_unsub TEXT,
        list_unsub_post TEXT,
        trashed INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS idx_messages_from ON messages(from_email);
      CREATE INDEX IF NOT EXISTS idx_messages_size ON messages(size);

      CREATE TABLE IF NOT EXISTS actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_ms INTEGER NOT NULL,
        kind TEXT NOT NULL,
        description TEXT NOT NULL,
        message_ids TEXT NOT NULL,
        count INTEGER NOT NULL,
        total_size INTEGER NOT NULL,
        undone_ms INTEGER
      );

      CREATE TABLE IF NOT EXISTS unsubscribe_status (
        sender TEXT PRIMARY KEY,
        done_ms INTEGER,
        body_links TEXT
      );

      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');
  }

  void close() => _db.close();

  // ---------------------------------------------------------------- cache

  Set<String> knownMessageIds() => _db
      .select('SELECT id FROM messages')
      .map((r) => r['id'] as String)
      .toSet();

  void upsertMessages(List<CachedMessage> messages) {
    if (messages.isEmpty) return;
    final stmt = _db.prepare('''
      INSERT INTO messages (id, thread_id, from_email, from_name, subject,
        date_ms, size, unread, labels, list_unsub, list_unsub_post, trashed)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
      ON CONFLICT(id) DO UPDATE SET
        unread = excluded.unread,
        labels = excluded.labels,
        trashed = 0
    ''');
    _db.execute('BEGIN');
    try {
      for (final m in messages) {
        stmt.execute([
          m.id,
          m.threadId,
          m.fromEmail,
          m.fromName,
          m.subject,
          m.dateMs,
          m.size,
          m.unread ? 1 : 0,
          jsonEncode(m.labels),
          m.listUnsubscribe,
          m.listUnsubscribePost,
        ]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.close();
    }
  }

  void _updateByIds(String sqlPrefix, List<String> ids) {
    const chunk = 500;
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, (i + chunk).clamp(0, ids.length));
      final marks = List.filled(part.length, '?').join(',');
      _db.execute('$sqlPrefix WHERE id IN ($marks)', part);
    }
  }

  void markTrashed(List<String> ids, {required bool trashed}) =>
      _updateByIds('UPDATE messages SET trashed = ${trashed ? 1 : 0}', ids);

  void removeMessages(List<String> ids) =>
      _updateByIds('DELETE FROM messages', ids);

  /// Remove do cache mensagens que não existem mais na caixa (apagadas ou
  /// movidas para a lixeira fora do Silver Mail).
  int pruneMissing(Set<String> presentIds) {
    final stale = knownMessageIds().difference(presentIds).toList();
    removeMessages(stale);
    return stale.length;
  }

  List<Map<String, Object?>> messagesByIds(List<String> ids, {int limit = 20}) {
    if (ids.isEmpty) return const [];
    final part = ids.take(500).toList();
    final marks = List.filled(part.length, '?').join(',');
    return _db
        .select(
          'SELECT * FROM messages WHERE id IN ($marks) '
          'ORDER BY date_ms DESC LIMIT ?',
          [...part, limit],
        )
        .map(_messageJson)
        .toList();
  }

  int sizeOfIds(List<String> ids) {
    var total = 0;
    const chunk = 500;
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, (i + chunk).clamp(0, ids.length));
      final marks = List.filled(part.length, '?').join(',');
      final row = _db.select(
        'SELECT COALESCE(SUM(size), 0) AS s FROM messages WHERE id IN ($marks)',
        part,
      );
      total += row.first['s'] as int;
    }
    return total;
  }

  // ---------------------------------------------------------------- consultas

  Map<String, Object?> stats() {
    final row = _db.select('''
      SELECT COUNT(*) AS total,
             COALESCE(SUM(size), 0) AS total_size,
             COALESCE(SUM(unread), 0) AS unread,
             COUNT(DISTINCT from_email) AS senders,
             COUNT(DISTINCT CASE WHEN list_unsub IS NOT NULL
                   THEN from_email END) AS with_unsubscribe,
             MIN(date_ms) AS oldest_ms
      FROM messages WHERE trashed = 0
    ''').first;
    return {
      'totalMessages': row['total'],
      'totalSize': row['total_size'],
      'unread': row['unread'],
      'senders': row['senders'],
      'sendersWithUnsubscribe': row['with_unsubscribe'],
      'oldestMs': row['oldest_ms'],
      'lastSyncMs': int.tryParse(getMeta('last_sync_ms') ?? ''),
    };
  }

  static const _senderSorts = {
    'count': 'count',
    'size': 'total_size',
    'unread': 'unread_ratio',
    'last': 'last_ms',
    'email': 'from_email',
  };

  Map<String, Object?> senders({
    String sort = 'count',
    bool descending = true,
    String? search,
    bool onlyWithUnsubscribe = false,
    int limit = 100,
    int offset = 0,
  }) {
    final orderBy = _senderSorts[sort] ?? 'count';
    final where = <String>['trashed = 0'];
    final args = <Object?>[];
    if (search != null && search.trim().isNotEmpty) {
      where.add('(from_email LIKE ? OR from_name LIKE ?)');
      args
        ..add('%${search.trim()}%')
        ..add('%${search.trim()}%');
    }
    final having = onlyWithUnsubscribe ? 'HAVING has_unsub = 1' : '';
    final base =
        '''
      SELECT from_email,
             MAX(from_name) AS from_name,
             COUNT(*) AS count,
             SUM(size) AS total_size,
             SUM(unread) AS unread,
             CAST(SUM(unread) AS REAL) / COUNT(*) AS unread_ratio,
             MAX(date_ms) AS last_ms,
             MIN(date_ms) AS first_ms,
             MAX(list_unsub IS NOT NULL) AS has_unsub
      FROM messages WHERE ${where.join(' AND ')}
      GROUP BY from_email $having
    ''';
    final total =
        _db.select('SELECT COUNT(*) AS c FROM ($base)', args).first['c'] as int;
    final rows = _db.select(
      '$base ORDER BY $orderBy ${descending ? 'DESC' : 'ASC'}, from_email '
      'LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return {
      'total': total,
      'items': rows
          .map(
            (r) => {
              'email': r['from_email'],
              'name': r['from_name'],
              'count': r['count'],
              'totalSize': r['total_size'],
              'unread': r['unread'],
              'unreadRatio': r['unread_ratio'],
              'lastMs': r['last_ms'],
              'firstMs': r['first_ms'],
              'hasUnsubscribe': r['has_unsub'] == 1,
            },
          )
          .toList(),
    };
  }

  List<Map<String, Object?>> messagesFromSender(
    String email, {
    int limit = 50,
  }) => _db
      .select(
        'SELECT * FROM messages WHERE from_email = ? AND trashed = 0 '
        'ORDER BY date_ms DESC LIMIT ?',
        [email, limit],
      )
      .map(_messageJson)
      .toList();

  List<Map<String, Object?>> largestMessages({int limit = 100}) => _db
      .select(
        'SELECT * FROM messages WHERE trashed = 0 ORDER BY size DESC LIMIT ?',
        [limit],
      )
      .map(_messageJson)
      .toList();

  /// Para cada remetente: o cabeçalho de descadastro mais recente.
  List<Map<String, Object?>> unsubscribeCandidates({
    bool includeWithoutHeader = false,
    int minCount = 1,
  }) {
    final rows = _db.select(
      '''
      WITH ranked AS (
        SELECT from_email, from_name, list_unsub, list_unsub_post, date_ms,
               ROW_NUMBER() OVER (
                 PARTITION BY from_email
                 ORDER BY (list_unsub IS NULL), date_ms DESC
               ) AS rn
        FROM messages WHERE trashed = 0
      ),
      agg AS (
        SELECT from_email, COUNT(*) AS count, SUM(unread) AS unread,
               MAX(date_ms) AS last_ms, SUM(size) AS total_size
        FROM messages WHERE trashed = 0 GROUP BY from_email
      )
      SELECT r.from_email, r.from_name, r.list_unsub, r.list_unsub_post,
             a.count, a.unread, a.last_ms, a.total_size,
             s.done_ms, s.body_links
      FROM ranked r
      JOIN agg a ON a.from_email = r.from_email
      LEFT JOIN unsubscribe_status s ON s.sender = r.from_email
      WHERE r.rn = 1 AND a.count >= ?
        ${includeWithoutHeader ? '' : 'AND r.list_unsub IS NOT NULL'}
      ORDER BY a.count DESC
      ''',
      [minCount],
    );
    return rows
        .map(
          (r) => {
            'email': r['from_email'],
            'name': r['from_name'],
            'listUnsubscribe': r['list_unsub'],
            'listUnsubscribePost': r['list_unsub_post'],
            'count': r['count'],
            'unread': r['unread'],
            'lastMs': r['last_ms'],
            'totalSize': r['total_size'],
            'doneMs': r['done_ms'],
            'bodyLinks': r['body_links'] == null
                ? null
                : jsonDecode(r['body_links'] as String),
          },
        )
        .toList();
  }

  String? latestMessageIdFrom(String email) {
    final rows = _db.select(
      'SELECT id FROM messages WHERE from_email = ? AND trashed = 0 '
      'ORDER BY date_ms DESC LIMIT 1',
      [email],
    );
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  void setUnsubscribeDone(String sender, {required bool done}) {
    _db.execute(
      '''
      INSERT INTO unsubscribe_status (sender, done_ms) VALUES (?, ?)
      ON CONFLICT(sender) DO UPDATE SET done_ms = excluded.done_ms
      ''',
      [sender, done ? DateTime.now().millisecondsSinceEpoch : null],
    );
  }

  void setBodyLinks(String sender, List<String> links) {
    _db.execute(
      '''
      INSERT INTO unsubscribe_status (sender, body_links) VALUES (?, ?)
      ON CONFLICT(sender) DO UPDATE SET body_links = excluded.body_links
      ''',
      [sender, jsonEncode(links)],
    );
  }

  // ---------------------------------------------------------------- histórico

  int recordAction({
    required String kind,
    required String description,
    required List<String> ids,
    required int totalSize,
  }) {
    _db.execute(
      'INSERT INTO actions (created_ms, kind, description, message_ids, count, '
      'total_size) VALUES (?, ?, ?, ?, ?, ?)',
      [
        DateTime.now().millisecondsSinceEpoch,
        kind,
        description,
        jsonEncode(ids),
        ids.length,
        totalSize,
      ],
    );
    return _db.lastInsertRowId;
  }

  List<Map<String, Object?>> history({int limit = 100}) => _db
      .select(
        'SELECT id, created_ms, kind, description, count, total_size, '
        'undone_ms FROM actions ORDER BY id DESC LIMIT ?',
        [limit],
      )
      .map(
        (r) => {
          'id': r['id'],
          'createdMs': r['created_ms'],
          'kind': r['kind'],
          'description': r['description'],
          'count': r['count'],
          'totalSize': r['total_size'],
          'undoneMs': r['undone_ms'],
          'undoable': r['kind'] == 'trash' && r['undone_ms'] == null,
        },
      )
      .toList();

  ({String kind, List<String> ids, bool undone})? action(int id) {
    final rows = _db.select(
      'SELECT kind, message_ids, undone_ms FROM actions WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      kind: r['kind'] as String,
      ids: (jsonDecode(r['message_ids'] as String) as List).cast<String>(),
      undone: r['undone_ms'] != null,
    );
  }

  void markActionUndone(int id) => _db.execute(
    'UPDATE actions SET undone_ms = ? WHERE id = ?',
    [DateTime.now().millisecondsSinceEpoch, id],
  );

  // ---------------------------------------------------------------- meta

  String? getMeta(String key) {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  void setMeta(String key, String value) => _db.execute(
    'INSERT INTO meta (key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );

  static Map<String, Object?> _messageJson(Row r) => {
    'id': r['id'],
    'threadId': r['thread_id'],
    'fromEmail': r['from_email'],
    'fromName': r['from_name'],
    'subject': r['subject'],
    'dateMs': r['date_ms'],
    'size': r['size'],
    'unread': r['unread'] == 1,
    'labels': jsonDecode(r['labels'] as String),
    'hasUnsubscribe': r['list_unsub'] != null,
  };
}
