param(
    [switch]$Web,
    [switch]$NoDocker,
    [switch]$ApiOnly,
    [string]$Device
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$RunDir = Join-Path $Root '.run'
$ApiPort = if ($env:EBT_API_PORT) { $env:EBT_API_PORT } else { '8080' }
$WebPort = '8081'
$ApiUrl = "http://localhost:$ApiPort"
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Has([string]$Command) { [bool](Get-Command $Command -ErrorAction SilentlyContinue) }

function Test-Port([int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try { $client.ConnectAsync('127.0.0.1', $Port).Wait(1000) -and $client.Connected } catch { $false } finally { $client.Dispose() }
}

function Wait-Api([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest "$ApiUrl/health" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Seconds 2
        Write-Host -NoNewline '.'
    }
    Write-Host ""
    return $false
}

function Test-DockerRunning {
    & docker info *> $null
    return $LASTEXITCODE -eq 0
}

if (-not $ApiOnly -and -not (Has 'flutter')) {
    Fail "Flutter not found in PATH. Install it from https://docs.flutter.dev/get-started/install/windows/desktop and reopen the terminal (or run with -ApiOnly)."
}

if (-not $NoDocker) {
    if (-not (Has 'docker')) {
        if (Has 'dotnet') {
            Write-Host "Docker not found, falling back to local mode (.NET + PostgreSQL on localhost:5432)." -ForegroundColor Yellow
            $NoDocker = $true
        } else {
            Fail "Neither Docker nor the .NET SDK was found. Install Docker Desktop (https://www.docker.com/products/docker-desktop/) or .NET 8 SDK + PostgreSQL 16 (https://dotnet.microsoft.com/download/dotnet/8.0, https://www.postgresql.org/download/windows/)."
        }
    } elseif (-not (Test-DockerRunning)) {
        Fail "Docker is installed but not running. Start Docker Desktop, wait until it says 'Engine running', then run this again. Or use -NoDocker with a local PostgreSQL."
    }
}

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

if (-not $NoDocker) {
    Step "Starting PostgreSQL + API with Docker (first run builds the image, takes a few minutes)"
    Push-Location $Root
    & docker compose up -d --build db api
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { Fail "docker compose failed. If port $ApiPort or 5432 is in use, set EBT_API_PORT / EBT_DB_PORT and retry." }
    'docker' | Set-Content (Join-Path $RunDir 'mode')
    Step "Waiting for API at $ApiUrl"
    if (-not (Wait-Api 300)) {
        Push-Location $Root; & docker compose logs --tail 60 api; Pop-Location
        Fail "API did not become healthy. Logs above."
    }
} else {
    if (-not (Has 'dotnet')) { Fail ".NET SDK not found. Install .NET 8 SDK: https://dotnet.microsoft.com/download/dotnet/8.0" }
    $sdks = & dotnet --list-sdks
    if (-not ($sdks | Where-Object { [int]($_.Split('.')[0]) -ge 8 })) { Fail ".NET 8 SDK (or newer) not found. Installed: $($sdks -join ', '). Get it at https://dotnet.microsoft.com/download/dotnet/8.0" }
    if (-not (Test-Port 5432)) {
        Fail "PostgreSQL is not reachable on localhost:5432. Install PostgreSQL 16 (https://www.postgresql.org/download/windows/) and start its service, or install Docker Desktop and run without -NoDocker."
    }
    if (Has 'psql') {
        $env:PGPASSWORD = 'ebt-dev-password'
        & psql -h localhost -U ebt -d ebt -c 'select 1' *> $null
        if ($LASTEXITCODE -ne 0) {
            Step "Creating role and database 'ebt' (psql will ask for the 'postgres' superuser password)"
            Remove-Item Env:PGPASSWORD
            & psql -h localhost -U postgres -c "CREATE ROLE ebt LOGIN PASSWORD 'ebt-dev-password'"
            & psql -h localhost -U postgres -c "CREATE DATABASE ebt OWNER ebt"
        }
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    } else {
        Write-Host "psql not in PATH; assuming role 'ebt' (password ebt-dev-password) and database 'ebt' exist." -ForegroundColor Yellow
    }
    if (Test-Port ([int]$ApiPort)) { Fail "Port $ApiPort is already in use. Run stop.bat or close whatever uses it." }
    Step "Starting API (dotnet run) in a new window"
    $apiArgs = @('run', '--project', ('"' + (Join-Path $Root 'src/Ebt.Api') + '"'), '--launch-profile', 'http', '--urls', $ApiUrl)
    if ($OnWindows) {
        $proc = Start-Process dotnet -ArgumentList $apiArgs -PassThru
    } else {
        $proc = Start-Process dotnet -ArgumentList $apiArgs -PassThru -RedirectStandardOutput (Join-Path $RunDir 'api.log') -RedirectStandardError (Join-Path $RunDir 'api.err.log')
    }
    $proc.Id | Set-Content (Join-Path $RunDir 'api.pid')
    'local' | Set-Content (Join-Path $RunDir 'mode')
    Step "Waiting for API at $ApiUrl (first run compiles, takes a minute)"
    if (-not (Wait-Api 240)) { Fail "API did not become healthy. Check the API window for errors (connection string: Host=localhost;Database=ebt;Username=ebt;Password=ebt-dev-password)." }
}

Write-Host ""
Write-Host "API      $ApiUrl   (Swagger: $ApiUrl/swagger)" -ForegroundColor Green
Write-Host "Login    admin / sidergest123" -ForegroundColor Green
Write-Host "Stop     stop.bat" -ForegroundColor Green
Write-Host ""

if ($ApiOnly) { exit 0 }

if (-not $Device) {
    if ($Web -or -not $OnWindows) { $Device = 'chrome' } else { $Device = 'windows' }
}

Push-Location (Join-Path $Root 'clients/flutter')
Step "flutter pub get"
& flutter pub get
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "flutter pub get failed." }

$flutterArgs = @('run', '-d', $Device, "--dart-define=API_URL=$ApiUrl")
if ($Device -in @('chrome', 'edge', 'web-server')) { $flutterArgs += @('--web-port', $WebPort) }
Step "flutter $($flutterArgs -join ' ')"
& flutter @flutterArgs
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) {
    if ($Device -eq 'windows') {
        Fail "flutter run failed. The Windows app needs Visual Studio 2022 with 'Desktop development with C++' (check: flutter doctor). Or run: start.bat -Web"
    }
    Fail "flutter run failed (device '$Device'). Check: flutter devices. Try -Device edge or -Device web-server."
}
