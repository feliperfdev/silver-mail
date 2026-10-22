import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Em produção o painel é servido pelo próprio servidor, então usa a mesma
/// origem. Em desenvolvimento: `--dart-define=API_BASE=http://127.0.0.1:8787`.
const _apiBaseOverride = String.fromEnvironment('API_BASE');

class ApiException implements Exception {
  ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Cliente HTTP da API local do servidor Dart.
class Api {
  Api()
    : base = Uri.parse(
        _apiBaseOverride.isNotEmpty ? _apiBaseOverride : Uri.base.origin,
      );

  final Uri base;
  final _http = http.Client();

  Uri uri(String path, [Map<String, String>? query]) =>
      base.replace(path: path, queryParameters: query);

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String>? query,
  ]) async => _decode(await _http.get(uri(path, query)));

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, Object?>? body,
  ]) async => _decode(
    await _http.post(
      uri(path),
      // Cabeçalho exigido pelo servidor em toda requisição que altera estado.
      headers: {'content-type': 'application/json', 'x-silver-mail': '1'},
      body: jsonEncode(body ?? const {}),
    ),
  );

  Map<String, dynamic> _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, json?['error'] as String? ?? text);
    }
    return json ?? {};
  }
}

/// Estado global: sessão e tarefa em andamento (sincronização ou ação).
class AppState extends ChangeNotifier {
  AppState(this.api);

  final Api api;

  Map<String, dynamic>? auth;
  Map<String, dynamic>? job;
  String? connectionError;

  /// Incrementado sempre que uma tarefa termina, para as telas recarregarem.
  int dataVersion = 0;

  Timer? _poll;

  bool get authenticated => auth?['authenticated'] == true;
  bool get canDeletePermanently => auth?['canDeletePermanently'] == true;
  bool get jobRunning => job?['running'] == true;

  Future<void> refreshAuth() async {
    try {
      auth = await api.get('/api/auth/status');
      connectionError = null;
    } catch (e) {
      connectionError =
          'Não foi possível falar com o servidor em ${api.base}. Ele está rodando?';
    }
    notifyListeners();
  }

  Future<void> init() async {
    await refreshAuth();
    await _refreshJob();
  }

  /// Registra uma tarefa recém-criada e acompanha o progresso até terminar.
  void trackJob(Map<String, dynamic> newJob) {
    job = newJob;
    notifyListeners();
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _refreshJob(),
    );
  }

  Future<void> _refreshJob() async {
    try {
      final wasRunning = jobRunning;
      job = (await api.get('/api/job'))['job'] as Map<String, dynamic>?;
      if (jobRunning && _poll == null) {
        _poll = Timer.periodic(
          const Duration(milliseconds: 800),
          (_) => _refreshJob(),
        );
      }
      if (!jobRunning) {
        _poll?.cancel();
        _poll = null;
        if (wasRunning) dataVersion++;
      }
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
