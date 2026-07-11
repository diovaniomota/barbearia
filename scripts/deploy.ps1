# TD Barbearia — build Flutter Web + deploy Cloudflare Workers
# Uso (PowerShell):
#   cd caminho\do\projeto
#   .\scripts\deploy.ps1

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "==> flutter pub get" -ForegroundColor Cyan
flutter pub get

Write-Host "==> flutter analyze (non-fatal warnings ok)" -ForegroundColor Cyan
flutter analyze --no-fatal-infos --no-fatal-warnings
if ($LASTEXITCODE -ne 0) {
  Write-Host "Analyze reportou issues — revisando, mas seguindo se o time permitir." -ForegroundColor Yellow
}

Write-Host "==> flutter test" -ForegroundColor Cyan
flutter test
if ($LASTEXITCODE -ne 0) {
  Write-Host "Testes falharam. Abortando deploy." -ForegroundColor Red
  exit 1
}

Write-Host "==> flutter build web --release" -ForegroundColor Cyan
flutter build web --release --base-href "/" --no-web-resources-cdn
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> wrangler deploy" -ForegroundColor Cyan
npx wrangler deploy
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "Deploy concluído." -ForegroundColor Green
