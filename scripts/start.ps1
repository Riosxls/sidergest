param(
    [switch]$Web,
    [switch]$NoDocker,
    [switch]$ApiOnly,
    [string]$Device
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$RunDir = Join-Path $Root '.run'
$ApiPort = if ($env:EBT_API_PORT) { [int]$env:EBT_API_PORT } else { 8080 }
$DbPort = if ($env:EBT_DB_PORT) { [int]$env:EBT_DB_PORT } elseif ($NoDocker) { 5432 } else { 25432 }
$WebPort = if ($env:EBT_WEB_PORT) { [int]$env:EBT_WEB_PORT } else { 8081 }
$ApiUrl = ''
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

function Test-Bindable([int]$Port) {
    if (Test-Port $Port) { return $false }
    foreach ($address in @([System.Net.IPAddress]::Any, [System.Net.IPAddress]::Loopback)) {
        $listener = New-Object System.Net.Sockets.TcpListener($address, $Port)
        try { $listener.Start() } catch { return $false } finally { try { $listener.Stop() } catch { } }
    }
    return $true
}

function Find-Port([int]$Start, [string]$Name) {
    for ($p = $Start; $p -lt $Start + 100; $p++) {
        if (Test-Bindable $p) {
            if ($p -ne $Start) { Write-Host "Port $Start ($Name) is in use or reserved by Windows, using $p." -ForegroundColor Yellow }
            return $p
        }
    }
    Fail "No free port for $Name between $Start and $($Start + 99). Set EBT_$($Name.ToUpper())_PORT to a free port."
}

function Get-ComposePort([string]$Service, [int]$Port) {
    $out = & docker compose port $Service $Port 2>$null
    if ($LASTEXITCODE -eq 0 -and $out -match ':(\d+)\s*$') { return [int]$Matches[1] }
    return 0
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

function Test-VsCpp {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $false }
    $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath
    return [bool]$path
}

function Show-AppHelp([string]$Reason) {
    Write-Host ""
    Write-Host "Windows app NOT launched: $Reason" -ForegroundColor Yellow
    Write-Host "The API keeps running. To run the app yourself:" -ForegroundColor Yellow
    Write-Host "  cd `"$(Join-Path $Root 'clients\flutter')`""
    Write-Host "  flutter pub get"
    Write-Host "  flutter run -d windows --dart-define=API_URL=$ApiUrl"
    Write-Host "Or in the browser:"
    Write-Host "  flutter run -d edge --web-port $WebPort --dart-define=API_URL=$ApiUrl"
    Write-Host ""
}

$FlutterMissing = -not (Has 'flutter')

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
    Push-Location $Root
    $runningApi = Get-ComposePort 'api' 8080
    $runningDb = Get-ComposePort 'db' 5432
    $ApiPort = if ($runningApi) { $runningApi } else { Find-Port $ApiPort 'api' }
    $DbPort = if ($runningDb) { $runningDb } else { Find-Port $DbPort 'db' }
    $WebPort = Find-Port $WebPort 'web'
    $ApiUrl = "http://localhost:$ApiPort"
    $env:EBT_API_PORT = "$ApiPort"
    $env:EBT_DB_PORT = "$DbPort"
    $env:EBT_CORS_ORIGIN = "http://localhost:$WebPort"
    Step "Starting PostgreSQL (port $DbPort) + API (port $ApiPort) with Docker (first run builds the image, takes a few minutes)"
    & docker compose up -d --build db api
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { Fail "docker compose failed (API port $ApiPort, DB port $DbPort). See the message above; if a port is 'forbidden by access permissions' set EBT_API_PORT / EBT_DB_PORT to another port and retry." }
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
    if (-not (Test-Port $DbPort)) {
        Fail "PostgreSQL is not reachable on localhost:$DbPort (set EBT_DB_PORT if it uses another port). Install PostgreSQL 16 (https://www.postgresql.org/download/windows/) and start its service, or install Docker Desktop and run without -NoDocker."
    }
    if (Has 'psql') {
        $env:PGPASSWORD = 'ebt-dev-password'
        & psql -h localhost -p $DbPort -U ebt -d ebt -c 'select 1' *> $null
        if ($LASTEXITCODE -ne 0) {
            Step "Creating role and database 'ebt' (psql will ask for the 'postgres' superuser password)"
            Remove-Item Env:PGPASSWORD
            & psql -h localhost -p $DbPort -U postgres -c "CREATE ROLE ebt LOGIN PASSWORD 'ebt-dev-password'"
            & psql -h localhost -p $DbPort -U postgres -c "CREATE DATABASE ebt OWNER ebt"
        }
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    } else {
        Write-Host "psql not in PATH; assuming role 'ebt' (password ebt-dev-password) and database 'ebt' exist." -ForegroundColor Yellow
    }
    $ApiPort = Find-Port $ApiPort 'api'
    $WebPort = Find-Port $WebPort 'web'
    $ApiUrl = "http://localhost:$ApiPort"
    $env:ConnectionStrings__Ebt = "Host=localhost;Port=$DbPort;Database=ebt;Username=ebt;Password=ebt-dev-password"
    $env:Cors__Origins__0 = "http://localhost:$WebPort"
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
    if (-not (Wait-Api 240)) { Fail "API did not become healthy. Check the API window for errors (connection string: Host=localhost;Port=$DbPort;Database=ebt;Username=ebt;Password=ebt-dev-password)." }
}

Write-Host ""
Write-Host "API      $ApiUrl   (Swagger: $ApiUrl/swagger)" -ForegroundColor Green
if (-not $NoDocker) { Write-Host "Postgres localhost:$DbPort  (ebt / ebt-dev-password)" -ForegroundColor Green }
if ($Web -or $Device -in @('chrome', 'edge', 'web-server')) { Write-Host "Web app  http://localhost:$WebPort" -ForegroundColor Green }
Write-Host "Login    admin / sidergest123" -ForegroundColor Green
Write-Host "Stop     stop.bat" -ForegroundColor Green
Write-Host ""

if ($ApiOnly) { exit 0 }

if ($FlutterMissing) {
    Write-Host "Flutter is not installed (or not in PATH)." -ForegroundColor Yellow
    Write-Host "  1. Download the Flutter SDK zip: https://docs.flutter.dev/get-started/install/windows/desktop"
    Write-Host "  2. Extract to C:\src\flutter and add C:\src\flutter\bin to PATH (Start > 'environment variables')"
    Write-Host "  3. Install Visual Studio 2022 Community with 'Desktop development with C++':"
    Write-Host "     winget install Microsoft.VisualStudio.2022.Community --override `"--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive`""
    Write-Host "  4. Open a new terminal, run: flutter doctor   then start.bat again"
    Show-AppHelp "Flutter not found."
    exit 0
}

if (-not $Device) {
    if ($Web -or -not $OnWindows) { $Device = 'chrome' } else { $Device = 'windows' }
}

if ($Device -eq 'windows' -and -not (Test-VsCpp)) {
    Write-Host "Visual Studio 'Desktop development with C++' not found; it is required to build the Windows app. Install with:" -ForegroundColor Yellow
    Write-Host "  winget install Microsoft.VisualStudio.2022.Community --override `"--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive`""
    Write-Host "Opening the app in Edge instead." -ForegroundColor Yellow
    $Device = 'edge'
}

Push-Location (Join-Path $Root 'clients/flutter')
Step "flutter pub get"
& flutter pub get
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "flutter pub get failed." }

$flutterArgs = @('run', '-d', $Device, "--dart-define=API_URL=$ApiUrl")
if ($Device -in @('chrome', 'edge', 'web-server')) { $flutterArgs += @('--web-port', $WebPort) }
if ($Device -eq 'windows') { Step "Launching the Windows app (first build takes a few minutes; press q here to quit it)" } else { Step "Launching the app in $Device at http://localhost:$WebPort (press q here to quit it)" }
Step "flutter $($flutterArgs -join ' ')"
& flutter @flutterArgs
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) {
    if ($Device -eq 'windows') { Show-AppHelp "flutter run failed (see above; check: flutter doctor)." } else { Show-AppHelp "flutter run -d $Device failed (check: flutter devices)." }
    exit 1
}
Write-Host "App closed. The API is still running at $ApiUrl; stop it with stop.bat." -ForegroundColor Green
