Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
Push-Location "$Root\backend"
npm install
Copy-Item .env.example .env -ErrorAction SilentlyContinue
Pop-Location
Push-Location "$Root\mobile"
flutter pub get
Pop-Location
Write-Host "Installation terminee. Configurez backend/.env puis lancez scripts/start-dev.ps1"
