param(
    [string]$ApiUrl     # the address the browser uses for the API. Default: https://<EBT_PUBLIC_HOST>, the same name the Caddy proxy serves (https://localhost without it)
)

# Builds the Flutter web app into clients\flutter\build\web, the folder the optional Caddy proxy serves (docker compose --profile proxy up -d caddy).
# With the proxy the app and the API share one address, so ApiUrl is just the public name. API_URL is compiled into the app: rebuild after changing it.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root 'clients\flutter'

if (-not $ApiUrl) {
    $hostName = $env:EBT_PUBLIC_HOST
    $envFile = Join-Path $Root '.env'
    if (-not $hostName -and (Test-Path $envFile)) {
        $line = Get-Content $envFile | Where-Object { $_ -like 'EBT_PUBLIC_HOST=*' } | Select-Object -First 1
        if ($line) { $hostName = ($line -replace '^EBT_PUBLIC_HOST=', '').Trim() }
    }
    $ApiUrl = if ($hostName) { "https://$hostName" } else { 'https://localhost' }
}
$ApiUrl = $ApiUrl.TrimEnd('/')
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter não encontrado no PATH.' }

Push-Location $App
try {
    Write-Host "==> flutter build web --release (API_URL=$ApiUrl)" -ForegroundColor Cyan
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falhou.' }
    & flutter build web --release "--dart-define=API_URL=$ApiUrl"
    if ($LASTEXITCODE -ne 0) { throw 'flutter build web falhou.' }
} finally {
    Pop-Location
}
Write-Host "Pronto: $(Join-Path $App 'build\web'). Suba o proxy com: docker compose --profile proxy up -d caddy" -ForegroundColor Green
