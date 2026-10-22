#!/usr/bin/env bash
# Compila o painel (se necessário) e sobe o servidor em http://127.0.0.1:8787
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -f "$ROOT/app/build/web/index.html" || "${1:-}" == "--rebuild" ]]; then
  echo "Compilando o painel Flutter Web..."
  (cd "$ROOT/app" && flutter pub get && flutter build web --release --no-web-resources-cdn)
fi

cd "$ROOT/server"
dart pub get
exec dart run bin/server.dart
