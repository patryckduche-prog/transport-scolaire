Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
Push-Location "$Root\backend"
docker compose up -d
npm run migrate
npm run seed
npm run dev
Pop-Location
