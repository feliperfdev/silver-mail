import 'dart:convert';

import 'package:googleapis/gmail/v1.dart';

import 'auth.dart';
import 'database.dart';
import 'parsing.dart';
import 'pool.dart';

const _metadataHeaders = [
  'From',
  'Subject',
  'List-Unsubscribe',
  'List-Unsubscribe-Post',
];

/// Progresso de uma tarefa longa (sincronização ou ação em massa).
class Job {
  Job(this.kind, this.description);

  final String kind;
  final String description;
  String phase = 'iniciando';
  int done = 0;
  int total = 0;
  bool running = true;
  String? error;
  Map<String, Object?>? result;
  final int startedMs = DateTime.now().millisecondsSinceEpoch;
  int? finishedMs;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'description': description,
    'phase': phase,
    'done': done,
    'total': total,
    'running': running,
    'error': error,
    'result': result,
    'startedMs': startedMs,
    'finishedMs': finishedMs,
  };
}

/// Operações sobre a caixa de entrada usando a Gmail API.
class GmailService {
  GmailService(this._auth, this._db);

  final AuthService _auth;
  final AppDatabase _db;

  Job? _job;
  Job? get job => _job;
  bool get busy => _job?.running ?? false;

  UsersMessagesResource get _messages => _auth.gmail.users.messages;

  /// Roda [body] como a tarefa atual. Só uma tarefa por vez, para não
  /// disputar a cota da API.
  Job runJob(String kind, String description, Future<void> Function(Job) body) {
    if (busy) {
      throw StateError(
        'Já existe uma tarefa em andamento: ${_job!.description}',
      );
    }
    final job = Job(kind, description);
    _job = job;
    _run(job, body);
    return job;
  }

  Future<void> _run(Job job, Future<void> Function(Job) body) async {
    try {
      await body(job);
      job.phase = 'concluído';
    } catch (e) {
      job
        ..error = e.toString()
        ..phase = 'erro';
    } finally {
      job
        ..running = false
        ..finishedMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  // ------------------------------------------------------------ sincronização

  /// Lista as mensagens que batem com [query] e baixa os metadados das que
  /// ainda não estão no cache. Sem [query], é uma sincronização completa e
  /// remove do cache o que não existe mais na caixa.
  Job startSync({String? query}) {
    final q = (query ?? '').trim();
    return runJob(
      'sync',
      q.isEmpty ? 'Sincronização completa' : 'Sincronizar: $q',
      (job) async {
        job.phase = 'listando mensagens';
        final ids = await listIds(q, onPage: (n) => job.done = n);

        final known = _db.knownMessageIds();
        final missing = ids.where((id) => !known.contains(id)).toList();
        job
          ..phase = 'baixando metadados'
          ..done = 0
          ..total = missing.length;

        final buffer = <CachedMessage>[];
        await forEachLimited(missing, (id) async {
          try {
            final msg = await withRetry(
              () => _messages.get(
                'me',
                id,
                format: 'metadata',
                metadataHeaders: _metadataHeaders,
                $fields: 'id,threadId,labelIds,sizeEstimate,internalDate,payload/headers',
              ),
            );
            buffer.add(_toCached(msg));
          } on DetailedApiRequestError catch (e) {
            // Mensagem apagada entre a listagem e o download.
            if (e.status != 404) rethrow;
          }
          job.done++;
          if (buffer.length >= 200) {
            _db.upsertMessages(List.of(buffer));
            buffer.clear();
          }
        });
        _db.upsertMessages(buffer);

        var pruned = 0;
        if (q.isEmpty) pruned = _db.pruneMissing(ids.toSet());
        _db.setMeta('last_sync_ms', '${DateTime.now().millisecondsSinceEpoch}');
        job.result = {
          'listed': ids.length,
          'downloaded': missing.length,
          'pruned': pruned,
        };
      },
    );
  }

  /// Todos os IDs que batem com a busca (fora lixeira e spam).
  Future<List<String>> listIds(
    String query, {
    void Function(int)? onPage,
  }) async {
    final ids = <String>[];
    String? pageToken;
    do {
      final page = await withRetry(
        () => _messages.list(
          'me',
          q: query.isEmpty ? null : query,
          maxResults: 500,
          pageToken: pageToken,
          includeSpamTrash: false,
          $fields: 'messages/id,nextPageToken',
        ),
      );
      ids.addAll((page.messages ?? const []).map((m) => m.id!));
      onPage?.call(ids.length);
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return ids;
  }

  CachedMessage _toCached(Message msg) {
    String? header(String name) {
      for (final h in msg.payload?.headers ?? const <MessagePartHeader>[]) {
        if (h.name?.toLowerCase() == name.toLowerCase()) return h.value;
      }
      return null;
    }

    final sender = parseFrom(header('From'));
    final labels = msg.labelIds ?? const <String>[];
    return CachedMessage(
      id: msg.id!,
      threadId: msg.threadId ?? '',
      fromEmail: sender.email,
      fromName: sender.name,
      subject: header('Subject') ?? '',
      dateMs: int.tryParse(msg.internalDate ?? '') ?? 0,
      size: msg.sizeEstimate ?? 0,
      unread: labels.contains('UNREAD'),
      labels: labels,
      listUnsubscribe: header('List-Unsubscribe'),
      listUnsubscribePost: header('List-Unsubscribe-Post'),
    );
  }

  // ------------------------------------------------------------ ações

  /// Converte remetentes em IDs consultando o Gmail ao vivo (não o cache),
  /// para que a prévia reflita exatamente o que existe agora.
  Future<List<String>> resolveSenders(List<String> senders) async {
    final ids = <String>{};
    for (final s in senders) {
      ids.addAll(await listIds('from:($s)'));
    }
    return ids.toList();
  }

  Future<void> trash(List<String> ids, Job job) async {
    job
      ..phase = 'movendo para a lixeira'
      ..total = ids.length;
    final ok = <String>[];
    await forEachLimited(ids, (id) async {
      await withRetry(() => _messages.trash('me', id, $fields: 'id'));
      ok.add(id);
      job.done++;
    });
    _db.markTrashed(ok, trashed: true);
  }

  Future<void> untrash(List<String> ids, Job job) async {
    job
      ..phase = 'restaurando da lixeira'
      ..total = ids.length;
    final ok = <String>[];
    await forEachLimited(ids, (id) async {
      try {
        await withRetry(() => _messages.untrash('me', id, $fields: 'id'));
        ok.add(id);
      } on DetailedApiRequestError catch (e) {
        // Já apagada de vez (lixeira esvaziada).
        if (e.status != 404) rethrow;
      }
      job.done++;
    });
    _db.markTrashed(ok, trashed: false);
    job.result = {'restored': ok.length, 'missing': ids.length - ok.length};
  }

  Future<void> deletePermanently(List<String> ids, Job job) async {
    if (!_auth.canDeletePermanently) {
      throw StateError(
        'Exclusão permanente não autorizada. Faça login novamente marcando '
        '"permitir exclusão permanente".',
      );
    }
    job
      ..phase = 'apagando permanentemente'
      ..total = ids.length;
    const chunk = 1000; // limite do batchDelete
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, (i + chunk).clamp(0, ids.length));
      await withRetry(
        () =>
            _messages.batchDelete(BatchDeleteMessagesRequest(ids: part), 'me'),
      );
      _db.removeMessages(part);
      job.done += part.length;
    }
  }

  // ------------------------------------------------------------ descadastro

  /// Lê o corpo da mensagem mais recente do remetente em busca de links de
  /// descadastro.
  Future<List<String>> scanBodyForUnsubscribe(String sender) async {
    final id = _db.latestMessageIdFrom(sender);
    if (id == null) return const [];
    final msg = await withRetry(() => _messages.get('me', id, format: 'full'));
    final html = StringBuffer();
    final text = StringBuffer();

    void walk(MessagePart? part) {
      if (part == null) return;
      final data = part.body?.data;
      if (data != null) {
        final decoded = utf8.decode(
          base64Url.decode(base64Url.normalize(data)),
          allowMalformed: true,
        );
        if (part.mimeType == 'text/html') html.writeln(decoded);
        if (part.mimeType == 'text/plain') text.writeln(decoded);
      }
      for (final child in part.parts ?? const <MessagePart>[]) {
        walk(child);
      }
    }

    walk(msg.payload);
    final links = findUnsubscribeLinksInBody(
      html: html.isEmpty ? null : html.toString(),
      text: text.isEmpty ? null : text.toString(),
    );
    _db.setBodyLinks(sender, links);
    return links;
  }
}
