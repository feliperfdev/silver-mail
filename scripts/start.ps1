# Compila o painel (se necessário) e sobe o servidor em http://127.0.0.1:8787
param([switch]$Rebuild)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if ($Rebuild -or -not (Test-Path "$Root/app/build/web/index.html")) {
  Write-Host "Compilando o painel Flutter Web..."
  Push-Location "$Root/app"
  flutter pub get
  flutter build web --release --no-web-resources-cdn
  Pop-Location
}

Set-Location "$Root/server"
dart pub get
dart run bin/server.dart
