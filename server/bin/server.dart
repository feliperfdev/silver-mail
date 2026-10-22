import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:silver_mail_server/silver_mail_server.dart';

Future<void> main(List<String> args) async {
  final scriptDir = p.dirname(p.dirname(Platform.script.toFilePath()));
  final env = Platform.environment;

  final port = int.tryParse(env['SILVER_MAIL_PORT'] ?? '') ?? 8787;
  final dataDir = env['SILVER_MAIL_HOME'] ?? p.join(scriptDir, 'data');
  final webDir =
      env['SILVER_MAIL_WEB'] ??
      p.normalize(p.join(scriptDir, '..', 'app', 'build', 'web'));

  final config = AppConfig(
    dataDir: dataDir,
    webDir: Directory(webDir).existsSync() ? webDir : null,
    port: port,
  )..ensureDataDir();

  final db = AppDatabase(config.databasePath);
  final auth = AuthService(config);
  await auth.restore();
  final gmail = GmailService(auth, db);
  final api = Api(auth, db, gmail);

  var cascade = Cascade().add(api.router.call);
  if (config.webDir != null) {
    cascade = cascade.add(
      createStaticHandler(config.webDir!, defaultDocument: 'index.html'),
    );
  }

  final handler = const Pipeline()
      .addMiddleware(localOnly())
      .addMiddleware(Api.errors())
      .addHandler(cascade.handler);

  // Só escuta na interface local: ninguém na sua rede acessa o painel.
  final server = await io.serve(handler, InternetAddress.loopbackIPv4, port);

  stdout
    ..writeln('Silver Mail rodando em http://127.0.0.1:${server.port}')
    ..writeln('Dados em: ${config.dataDir}')
    ..writeln(
      config.webDir == null
          ? 'Painel não compilado — rode "flutter build web" em app/ '
                'ou use "flutter run -d web-server" em modo dev.'
          : 'Painel servido de: ${config.webDir}',
    )
    ..writeln(
      config.hasClientSecret
          ? (auth.isAuthenticated
                ? 'Conectado como ${auth.email}'
                : 'Abra o painel e clique em "Entrar com Google".')
          : 'ATENÇÃO: coloque o client_secret.json em ${config.clientSecretPath}',
    );

  ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    db.close();
    exit(0);
  });
}
