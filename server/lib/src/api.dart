import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'database.dart';
import 'gmail_service.dart';
import 'parsing.dart';

class _Preview {
  _Preview(this.action, this.description, this.ids, this.totalSize);

  final String action;
  final String description;
  final List<String> ids;
  final int totalSize;
  final DateTime expiresAt = DateTime.now().add(const Duration(minutes: 15));
}

/// Rotas HTTP consumidas pelo painel.
class Api {
  Api(this._auth, this._db, this._gmail);

  final AuthService _auth;
  final AppDatabase _db;
  final GmailService _gmail;
  final _previews = <String, _Preview>{};
  final _random = Random.secure();

  Router get router {
    final r = Router();

    // ---- autenticação
    r.get('/api/auth/status', (Request _) => _json(_auth.status()));
    r.post('/api/auth/login', (Request req) async {
      final body = await _body(req);
      final url = await _auth.startLogin(
        permanentDelete: body['permanentDelete'] == true,
      );
      return _json({'url': url});
    });
    r.post('/api/auth/logout', (Request _) async {
      await _auth.logout();
      return _json({'ok': true});
    });

    // ---- visão geral e sincronização
    r.get('/api/stats', (Request _) => _json(_db.stats()));
    r.get('/api/job', (Request _) => _json({'job': _gmail.job?.toJson()}));
    r.post('/api/sync', (Request req) async {
      _requireAuth();
      final body = await _body(req);
      final job = _gmail.startSync(query: body['query'] as String?);
      return _json({'job': job.toJson()});
    });

    // ---- remetentes
    r.get('/api/senders', (Request req) {
      final q = req.url.queryParameters;
      return _json(
        _db.senders(
          sort: q['sort'] ?? 'count',
          descending: q['order'] != 'asc',
          search: q['search'],
          onlyWithUnsubscribe: q['onlyUnsubscribe'] == 'true',
          limit: int.tryParse(q['limit'] ?? '') ?? 100,
          offset: int.tryParse(q['offset'] ?? '') ?? 0,
        ),
      );
    });
    r.get('/api/senders/<email>/messages', (Request req, String email) {
      return _json({
        'items': _db.messagesFromSender(Uri.decodeComponent(email)),
      });
    });

    // ---- ações em massa: prévia -> execução -> histórico/desfazer
    r.post('/api/actions/preview', (Request req) async {
      _requireAuth();
      final body = await _body(req);
      final action = body['action'] as String? ?? 'trash';
      if (action != 'trash' && action != 'delete') {
        return _error(400, 'Ação inválida: $action');
      }
      if (action == 'delete' && !_auth.canDeletePermanently) {
        return _error(
          403,
          'Exclusão permanente não autorizada. Faça login novamente marcando '
          '"permitir exclusão permanente".',
        );
      }

      final List<String> ids;
      final String description;
      final senders = (body['senders'] as List?)?.cast<String>();
      final query = (body['query'] as String?)?.trim();
      if (senders != null && senders.isNotEmpty) {
        ids = await _gmail.resolveSenders(senders);
        description = senders.length == 1
            ? 'Remetente ${senders.first}'
            : '${senders.length} remetentes: ${senders.take(3).join(', ')}'
                  '${senders.length > 3 ? '…' : ''}';
      } else if (query != null && query.isNotEmpty) {
        ids = await _gmail.listIds(query);
        description = 'Busca "$query"';
      } else {
        return _error(400, 'Informe "senders" ou "query".');
      }

      _previews.removeWhere((_, p) => p.expiresAt.isBefore(DateTime.now()));
      final token = List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final totalSize = _db.sizeOfIds(ids);
      _previews[token] = _Preview(action, description, ids, totalSize);

      return _json({
        'token': token,
        'action': action,
        'description': description,
        'count': ids.length,
        'totalSize': totalSize,
        'sample': _db.messagesByIds(ids, limit: 25),
      });
    });

    r.post('/api/actions/execute', (Request req) async {
      _requireAuth();
      final body = await _body(req);
      final preview = _previews.remove(body['token']);
      if (preview == null || preview.expiresAt.isBefore(DateTime.now())) {
        return _error(410, 'Prévia expirada. Gere uma nova prévia.');
      }
      final label = preview.action == 'trash'
          ? 'Lixeira: ${preview.description}'
          : 'Exclusão permanente: ${preview.description}';
      final job = _gmail.runJob(preview.action, label, (job) async {
        if (preview.action == 'trash') {
          await _gmail.trash(preview.ids, job);
        } else {
          await _gmail.deletePermanently(preview.ids, job);
        }
        final id = _db.recordAction(
          kind: preview.action,
          description: preview.description,
          ids: preview.ids,
          totalSize: preview.totalSize,
        );
        job.result = {'actionId': id, 'count': preview.ids.length};
      });
      return _json({'job': job.toJson()});
    });

    r.get(
      '/api/actions/history',
      (Request _) => _json({'items': _db.history()}),
    );

    r.post('/api/actions/<id>/undo', (Request req, String id) {
      _requireAuth();
      final actionId = int.parse(id);
      final action = _db.action(actionId);
      if (action == null) return _error(404, 'Ação não encontrada.');
      if (action.kind != 'trash') {
        return _error(400, 'Exclusões permanentes não podem ser desfeitas.');
      }
      if (action.undone) return _error(400, 'Esta ação já foi desfeita.');
      final job = _gmail.runJob('untrash', 'Desfazer ação #$actionId', (
        job,
      ) async {
        await _gmail.untrash(action.ids, job);
        _db.markActionUndone(actionId);
      });
      return _json({'job': job.toJson()});
    });

    // ---- descadastro
    r.get('/api/unsubscribe', (Request req) {
      final q = req.url.queryParameters;
      return _json({
        'items': _unsubscribeItems(
          includeWithoutHeader: q['withoutHeader'] == 'true',
          includeDone: q['includeDone'] != 'false',
        ),
      });
    });
    r.post('/api/unsubscribe/<email>/scan', (Request req, String email) async {
      _requireAuth();
      final links = await _gmail.scanBodyForUnsubscribe(
        Uri.decodeComponent(email),
      );
      return _json({'links': links});
    });
    r.post('/api/unsubscribe/<email>/done', (Request req, String email) async {
      final body = await _body(req);
      _db.setUnsubscribeDone(
        Uri.decodeComponent(email),
        done: body['done'] != false,
      );
      return _json({'ok': true});
    });
    r.get('/api/unsubscribe/export', (Request req) {
      final format = req.url.queryParameters['format'] ?? 'csv';
      final items = _unsubscribeItems(includeWithoutHeader: false);
      final isCsv = format != 'md';
      return Response.ok(
        isCsv ? _toCsv(items) : _toMarkdown(items),
        headers: {
          'content-type': isCsv
              ? 'text/csv; charset=utf-8'
              : 'text/markdown; charset=utf-8',
          'content-disposition':
              'attachment; filename="descadastro.${isCsv ? 'csv' : 'md'}"',
        },
      );
    });

    return r;
  }

  List<Map<String, Object?>> _unsubscribeItems({
    required bool includeWithoutHeader,
    bool includeDone = true,
  }) {
    return _db
        .unsubscribeCandidates(includeWithoutHeader: includeWithoutHeader)
        .where((i) => includeDone || i['doneMs'] == null)
        .map((i) {
          final links = parseListUnsubscribe(
            i['listUnsubscribe'] as String?,
            i['listUnsubscribePost'] as String?,
          );
          return {
            'email': i['email'],
            'name': i['name'],
            'count': i['count'],
            'unread': i['unread'],
            'lastMs': i['lastMs'],
            'totalSize': i['totalSize'],
            'doneMs': i['doneMs'],
            'links': links.toJson(),
            'bodyLinks': i['bodyLinks'],
          };
        })
        .toList();
  }

  String _toCsv(List<Map<String, Object?>> items) {
    String cell(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final out = StringBuffer(
      'remetente,nome,emails,nao_lidos,ultimo_envio,um_clique,link,mailto,feito\n',
    );
    for (final i in items) {
      final links = i['links'] as Map<String, Object>;
      final http = links['http'] as List<String>;
      final mailto = links['mailto'] as List<String>;
      out.writeln(
        [
          i['email'],
          i['name'],
          i['count'],
          i['unread'],
          _isoDate(i['lastMs'] as int?),
          links['oneClick'] == true ? 'sim' : 'nao',
          http.isEmpty ? '' : http.first,
          mailto.isEmpty ? '' : mailto.first,
          i['doneMs'] == null ? 'nao' : 'sim',
        ].map(cell).join(','),
      );
    }
    return out.toString();
  }

  String _toMarkdown(List<Map<String, Object?>> items) {
    final out = StringBuffer('# Links de descadastro\n\n');
    for (final i in items) {
      final links = i['links'] as Map<String, Object>;
      final http = links['http'] as List<String>;
      final mailto = links['mailto'] as List<String>;
      final done = i['doneMs'] == null ? ' ' : 'x';
      final name = (i['name'] as String?)?.isNotEmpty == true
          ? '${i['name']} '
          : '';
      final target = http.isNotEmpty
          ? '[descadastrar](${http.first})'
          : '[enviar e-mail](${mailto.first})';
      out.writeln(
        '- [$done] **$name<${i['email']}>** — ${i['count']} e-mails, '
        '${i['unread']} não lidos — $target',
      );
    }
    return out.toString();
  }

  static String _isoDate(int? ms) => ms == null
      ? ''
      : DateTime.fromMillisecondsSinceEpoch(ms)
            .toIso8601String()
            .split('T')
            .first;

  void _requireAuth() {
    if (!_auth.isAuthenticated) {
      throw const _HttpError(401, 'Faça login primeiro.');
    }
  }

  static Future<Map<String, dynamic>> _body(Request req) async {
    final raw = await req.readAsString();
    if (raw.trim().isEmpty) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Response _json(Object? data, {int status = 200}) => Response(
    status,
    body: jsonEncode(data),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  static Response _error(int status, String message) =>
      _json({'error': message}, status: status);

  /// Converte exceções em respostas JSON legíveis pelo painel.
  static Middleware errors() =>
      (inner) => (req) async {
        try {
          return await inner(req);
        } on _HttpError catch (e) {
          return _error(e.status, e.message);
        } on StateError catch (e) {
          return _error(409, e.message);
        } catch (e, st) {
          stderr.writeln('Erro em ${req.method} ${req.requestedUri}: $e\n$st');
          return _error(500, e.toString());
        }
      };
}

class _HttpError implements Exception {
  const _HttpError(this.status, this.message);

  final int status;
  final String message;
}

/// Proteções para um servidor local com ações destrutivas:
///
/// * rejeita `Host` que não seja localhost (contra DNS rebinding);
/// * exige o cabeçalho `X-Silver-Mail` em requisições que alteram estado,
///   o que obriga um preflight CORS — e o CORS só libera origens locais.
Middleware localOnly() {
  bool isLocal(String? host) {
    if (host == null) return false;
    final name = host.startsWith('[')
        ? host.substring(0, host.indexOf(']') + 1)
        : host.split(':').first;
    return name == 'localhost' || name == '127.0.0.1' || name == '[::1]';
  }

  bool isLocalOrigin(String? origin) =>
      origin != null && isLocal(Uri.tryParse(origin)?.authority);

  return (inner) => (req) async {
    if (!isLocal(req.headers['host'])) {
      return Response.forbidden('Host não permitido.');
    }
    final origin = req.headers['origin'];
    final cors = <String, String>{
      if (isLocalOrigin(origin)) ...{
        'access-control-allow-origin': origin!,
        'access-control-allow-methods': 'GET, POST, OPTIONS',
        'access-control-allow-headers': 'content-type, x-silver-mail',
        'vary': 'origin',
      },
    };
    if (req.method == 'OPTIONS') return Response.ok('', headers: cors);
    if (origin != null && !isLocalOrigin(origin)) {
      return Response.forbidden('Origem não permitida.');
    }
    final mutating = req.method != 'GET' && req.method != 'HEAD';
    if (mutating &&
        req.url.path.startsWith('api/') &&
        req.headers['x-silver-mail'] != '1') {
      return Response.forbidden('Cabeçalho X-Silver-Mail ausente.');
    }
    final res = await inner(req);
    return res.change(headers: cors);
  };
}
