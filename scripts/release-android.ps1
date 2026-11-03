param(
    [string]$ApiUrl,        # the server the app talks to; must be https:// (release builds block plain HTTP). Default: https://<EBT_PUBLIC_HOST>
    [switch]$Bump,          # add 1 to the build number in pubspec.yaml (version: 1.0.0+N) before building
    [switch]$Bundle         # also build the app bundle (.aab) for the Play Store
)

# Builds the signed Android release (APK, and the .aab with -Bundle), copies it to releases\ and prints its SHA-256.
# Signing comes from clients\flutter\android\key.properties (storeFile, storePassword, keyAlias, keyPassword); without it the build falls back to the
# debug key with a warning and the file name says "debug-signed". Create the keystore once (docs\OPERATIONS.md, "Android release signing") and
# keep a copy of it OFF this computer: an app signed with a lost key can never be updated.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root 'clients\flutter'
$Releases = Join-Path $Root 'releases'

function Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

if (-not $ApiUrl) {
    $hostName = $env:EBT_PUBLIC_HOST
    $envFile = Join-Path $Root '.env'
    if (-not $hostName -and (Test-Path $envFile)) {
        $line = Get-Content $envFile | Where-Object { $_ -like 'EBT_PUBLIC_HOST=*' } | Select-Object -First 1
        if ($line) { $hostName = ($line -replace '^EBT_PUBLIC_HOST=', '').Trim() }
    }
    $ApiUrl = if ($hostName) { "https://$hostName" } else { 'https://metagest.local' }
}
$ApiUrl = $ApiUrl.TrimEnd('/')
if ($ApiUrl -notmatch '^https://') { Write-Host "AVISO: $ApiUrl não é https://. O Android (release) bloqueia HTTP puro; o app não vai conseguir entrar." -ForegroundColor Yellow }
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter não encontrado no PATH.' }

$signed = Test-Path (Join-Path $App 'android\key.properties')
if (-not $signed) { Write-Host 'AVISO: android\key.properties não existe; o APK será assinado com a chave de DEBUG e não deve ser distribuído.' -ForegroundColor Yellow }

$pubspec = Join-Path $App 'pubspec.yaml'
$raw = [IO.File]::ReadAllText($pubspec)
if ($raw -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)') { throw 'Não achei "version: x.y.z+N" no pubspec.yaml.' }
$name = $Matches[1]
$build = [int]$Matches[2]
if ($Bump) {
    $build++
    # Replace only the number, so the file keeps its line endings.
    $raw = [regex]::Replace($raw, '(?m)^(version:\s*\d+\.\d+\.\d+\+)\d+', "`${1}$build")
    [IO.File]::WriteAllText($pubspec, $raw, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Versão: $name+$build (número do build aumentado)"
} else {
    Write-Host "Versão: $name+$build (use -Bump para aumentar o número do build)"
}

New-Item -ItemType Directory -Force -Path $Releases | Out-Null
$suffix = if ($signed) { '' } else { '-debug-signed' }

Push-Location $App
try {
    Step 'flutter pub get'
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falhou.' }

    Step "flutter build apk --release (API_URL=$ApiUrl)"
    & flutter build apk --release "--dart-define=API_URL=$ApiUrl"
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk falhou.' }
    $apk = Join-Path $Releases "metagest-$name+$build$suffix.apk"
    Copy-Item (Join-Path $App 'build\app\outputs\flutter-apk\app-release.apk') $apk -Force
    Write-Host "APK:    $apk"
    Write-Host "SHA-256 $((Get-FileHash $apk -Algorithm SHA256).Hash)"

    if ($Bundle) {
        Step "flutter build appbundle --release (API_URL=$ApiUrl)"
        & flutter build appbundle --release "--dart-define=API_URL=$ApiUrl"
        if ($LASTEXITCODE -ne 0) { throw 'flutter build appbundle falhou.' }
        $aab = Join-Path $Releases "metagest-$name+$build$suffix.aab"
        Copy-Item (Join-Path $App 'build\app\outputs\bundle\release\app-release.aab') $aab -Force
        Write-Host "AAB:    $aab"
        Write-Host "SHA-256 $((Get-FileHash $aab -Algorithm SHA256).Hash)"
    }
} finally {
    Pop-Location
}
if ($signed) { Write-Host 'Pronto. Guarde uma cópia do keystore fora deste computador.' -ForegroundColor Green } else { Write-Host 'Pronto (assinado com a chave de debug).' -ForegroundColor Yellow }
