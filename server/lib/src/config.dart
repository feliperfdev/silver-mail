import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:path/path.dart' as p;

/// Caminhos e configurações do servidor.
///
/// Por padrão tudo fica em `server/data/`, que está no `.gitignore`.
/// Defina `SILVER_MAIL_HOME` para usar outro diretório.
class AppConfig {
  AppConfig({required this.dataDir, required this.webDir, required this.port});

  final String dataDir;
  final String? webDir;
  final int port;

  String get clientSecretPath => p.join(dataDir, 'client_secret.json');
  String get tokenPath => p.join(dataDir, 'token.json');
  String get databasePath => p.join(dataDir, 'silver_mail.db');

  bool get hasClientSecret => File(clientSecretPath).existsSync();

  /// Lê o JSON baixado do Google Cloud (cliente OAuth do tipo "App para computador").
  ClientId loadClientId() {
    final raw = jsonDecode(
      File(clientSecretPath).readAsStringSync(),
    ) as Map<String, dynamic>;
    final section = (raw['installed'] ?? raw['web']) as Map<String, dynamic>?;
    if (section == null) {
      throw const FormatException(
        'client_secret.json inválido: esperado um objeto "installed".',
      );
    }
    return ClientId(
      section['client_id'] as String,
      section['client_secret'] as String?,
    );
  }

  void ensureDataDir() => Directory(dataDir).createSync(recursive: true);
}
