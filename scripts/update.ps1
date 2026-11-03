param(
    [switch]$Force,          # update even with uncommitted changes under src\ (the image is then tagged <sha>-dirty)
    [int]$WaitSeconds = 90   # how long the new api may take to answer /health/ready before it is rolled back
)

# One safe way to put new code into the running API container on this computer:
#   1. refuses to run with uncommitted changes under src\ (unless -Force), so the image always matches a commit;
#   2. takes a verified backup (scripts\backup.ps1 -Reason before-rebuild) and stops if it fails;
#   3. keeps the current image as metagest-api:previous, builds the new one as metagest-api:<sha> and metagest-api:latest;
#   4. recreates ONLY the api container (db is never touched) and waits for GET /health/ready;
#   5. if it does not answer in time, puts the previous image back and exits with an error.
# A rollback restores the old code, not the old data: the new API runs the migrations when it starts, so a schema change may already be
# applied. If the old code cannot work with it, restore the dump of step 2 (docs\OPERATIONS.md, "Updating the API").
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Image = 'metagest-api'

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "ERRO: $Message" -ForegroundColor Red
    exit 1
}
function Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Get-ImageId([string]$Tag) {
    $id = & docker image inspect -f '{{.Id}}' $Tag 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($id | Select-Object -First 1)
}

function Get-ApiUrl {
    $out = & docker compose -p metagest port api 8080 2>$null
    if ($LASTEXITCODE -eq 0 -and $out -match ':(\d+)\s*$') { return "http://localhost:$($Matches[1])" }
    $port = if ($env:EBT_API_PORT) { $env:EBT_API_PORT } else { '8080' }
    return "http://localhost:$port"
}

# True when GET /health/ready answers 200 ("ok" or "degraded": backup warnings do not block an update). A 503 or no answer is false.
function Wait-Ready([int]$Seconds) {
    $url = (Get-ApiUrl) + '/health/ready'
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -eq 200) {
                $body = $r.Content | ConvertFrom-Json
                if ($body.backup -and $body.warnings -and @($body.warnings).Count -gt 0) {
                    Write-Host ""
                    Write-Host "Aviso do sistema: $(@($body.warnings) -join ', ') (veja Configurações > Administração > Cópia de segurança)." -ForegroundColor Yellow
                }
                return $true
            }
        } catch { }
        Start-Sleep -Seconds 2
        Write-Host -NoNewline '.'
    }
    Write-Host ""
    return $false
}

function Restart-Api {
    & docker compose -p metagest up -d --no-deps --force-recreate --pull never api
    return ($LASTEXITCODE -eq 0)
}

Push-Location $Root
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Fail 'Docker não encontrado.' }
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { Fail 'O Docker não está rodando. Abra o Docker Desktop e tente de novo.' }
    $dbRunning = & docker compose -p metagest ps --status running -q db 2>$null
    if (-not $dbRunning) { Fail 'O banco (container db) não está rodando; nada para atualizar. Use start.bat.' }

    # 1. The image must match a commit.
    $sha = 'local'
    if (Test-Path (Join-Path $Root '.git')) {
        $dirty = @(& git -C $Root status --porcelain -- src 2>$null)
        if ($dirty.Count -gt 0 -and -not $Force) {
            Write-Host ($dirty -join "`n")
            Fail 'Há alterações não salvas (commit) em src\. Faça o commit ou use -Force.'
        }
        $sha = (& git -C $Root rev-parse --short HEAD 2>$null | Select-Object -First 1)
        if (-not $sha) { $sha = 'local' }
        if ($dirty.Count -gt 0) { $sha = "$sha-dirty" }
    }

    # 2. Backup first; the new API migrates the schema on start.
    Step 'Fazendo backup antes de atualizar'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'backup.ps1') -Reason before-rebuild -Quiet
    if ($LASTEXITCODE -ne 0) { Fail 'O backup falhou, então a atualização foi cancelada e nada foi alterado. Resolva o backup (mensagem acima) ou rode scripts\backup.ps1.' }

    # 3. Keep the running image as "previous", then build the new one.
    $oldId = Get-ImageId "${Image}:latest"
    if ($oldId) {
        & docker tag $oldId "${Image}:previous"
        Write-Host "Imagem atual guardada como ${Image}:previous"
    } else {
        Write-Host 'Não há imagem anterior (primeira instalação); sem como voltar atrás.' -ForegroundColor Yellow
    }
    Step "Construindo a imagem ${Image}:$sha"
    & docker build --target api -t "${Image}:$sha" -t "${Image}:latest" $Root
    if ($LASTEXITCODE -ne 0) { Fail 'A construção da imagem falhou. O sistema continua rodando com a versão anterior.' }
    $newId = Get-ImageId "${Image}:latest"

    # 4. Recreate only the api container.
    Step 'Trocando o container da API (o banco não é tocado)'
    if (-not (Restart-Api)) { Fail 'docker compose não conseguiu recriar a API. Veja a mensagem acima.' }
    Step "Esperando a API responder em /health/ready (até $WaitSeconds s)"
    if (Wait-Ready $WaitSeconds) {
        Write-Host ""
        Write-Host "Atualização concluída: ${Image}:$sha está no ar." -ForegroundColor Green
        if ($oldId -and $oldId -ne $newId) { Write-Host "Para voltar: docker tag ${Image}:previous ${Image}:latest; docker compose -p metagest up -d --no-deps --force-recreate --pull never api" }
        exit 0
    }

    # 5. Roll back the code.
    Write-Host ""
    Write-Host 'A API nova não ficou pronta a tempo. Últimas linhas do log:' -ForegroundColor Yellow
    & docker compose -p metagest logs --tail 40 api
    if ($oldId) {
        Step 'Voltando para a imagem anterior'
        & docker tag "${Image}:previous" "${Image}:latest"
        $restarted = Restart-Api
        $back = $restarted -and (Wait-Ready 60)
        if ($back) { Write-Host 'A versão anterior voltou a responder.' -ForegroundColor Yellow } else { Write-Host 'A versão anterior também não respondeu; veja o log acima.' -ForegroundColor Red }
    }
    Write-Host ""
    Write-Host 'ATENÇÃO: a API nova pode já ter aplicado uma migração no banco antes de falhar. Se a versão anterior não funciona com o banco atual,' -ForegroundColor Red
    Write-Host 'restaure o backup feito no início desta atualização (backups\ebt-before-rebuild-*.dump); veja docs\OPERATIONS.md, "Updating the API".' -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
