import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis/gmail/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

const scopeModify = 'https://www.googleapis.com/auth/gmail.modify';
const scopeFullAccess = 'https://mail.google.com/';

/// Cuida do login OAuth, da persistência do token e do cliente autenticado.
class AuthService {
  AuthService(this._config);

  final AppConfig _config;

  AutoRefreshingAuthClient? _client;
  StreamSubscription<AccessCredentials>? _updatesSub;
  String? _email;
  String? _pendingUrl;
  String? _lastError;

  bool get isAuthenticated => _client != null;
  String? get email => _email;

  List<String> get grantedScopes => _client?.credentials.scopes ?? const [];

  /// Exclusão permanente exige o escopo total do Gmail.
  bool get canDeletePermanently => grantedScopes.contains(scopeFullAccess);

  GmailApi get gmail {
    final client = _client;
    if (client == null) throw StateError('Não autenticado.');
    return GmailApi(client);
  }

  Map<String, Object?> status() => {
    'configured': _config.hasClientSecret,
    'authenticated': isAuthenticated,
    'email': _email,
    'scopes': grantedScopes,
    'canDeletePermanently': canDeletePermanently,
    'pendingLoginUrl': _pendingUrl,
    'lastError': _lastError,
  };

  /// Restaura a sessão salva em disco, se existir.
  Future<void> restore() async {
    final file = File(_config.tokenPath);
    if (!file.existsSync() || !_config.hasClientSecret) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final credentials = AccessCredentials.fromJson(
        json['credentials'] as Map<String, dynamic>,
      );
      _email = json['email'] as String?;
      _setClient(
        autoRefreshingClient(
          _config.loadClientId(),
          credentials,
          http.Client(),
        ),
      );
      // Força uma chamada para validar o refresh token.
      final profile = await gmail.users.getProfile('me');
      _email = profile.emailAddress;
      _persist();
    } catch (e) {
      stderr.writeln('Não foi possível restaurar a sessão: $e');
      _lastError =
          'Sessão expirada ou revogada. Faça login novamente. Detalhe: $e';
      await logout();
    }
  }

  /// Inicia o fluxo de consentimento e devolve a URL que o usuário deve abrir.
  ///
  /// O `googleapis_auth` sobe um servidor temporário em `localhost` para
  /// receber o retorno do Google; a conclusão acontece em segundo plano.
  Future<String> startLogin({required bool permanentDelete}) async {
    if (!_config.hasClientSecret) {
      throw StateError(
        'Arquivo ${_config.clientSecretPath} não encontrado. Veja o README.',
      );
    }
    final scopes = [permanentDelete ? scopeFullAccess : scopeModify];
    final urlCompleter = Completer<String>();
    _lastError = null;

    unawaited(
      clientViaUserConsent(_config.loadClientId(), scopes, (url) {
            // Garante refresh token e que a tela de consentimento mostre os
            // escopos novos ao trocar de permissão.
            final uri = Uri.parse(url);
            final withOffline = uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                'access_type': 'offline',
                'prompt': 'consent',
              },
            );
            _pendingUrl = withOffline.toString();
            urlCompleter.complete(_pendingUrl);
          })
          .then((client) async {
            _setClient(client);
            final profile = await gmail.users.getProfile('me');
            _email = profile.emailAddress;
            _persist();
          })
          .catchError((Object e) {
            _lastError = 'Falha no login: $e';
            if (!urlCompleter.isCompleted) urlCompleter.completeError(e);
          })
          .whenComplete(() => _pendingUrl = null),
    );

    return urlCompleter.future;
  }

  Future<void> logout() async {
    await _updatesSub?.cancel();
    _updatesSub = null;
    _client?.close();
    _client = null;
    _email = null;
    final file = File(_config.tokenPath);
    if (file.existsSync()) file.deleteSync();
  }

  void _setClient(AutoRefreshingAuthClient client) {
    _updatesSub?.cancel();
    _client?.close();
    _client = client;
    _updatesSub = client.credentialUpdates.listen((_) => _persist());
  }

  void _persist() {
    final client = _client;
    if (client == null) return;
    final file = File(_config.tokenPath);
    file.writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'email': _email, 'credentials': client.credentials.toJson()}),
    );
    if (!Platform.isWindows) {
      // Token dá acesso ao seu e-mail: só o seu usuário pode ler.
      Process.runSync('chmod', ['600', file.path]);
    }
  }
}
