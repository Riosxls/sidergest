# Opt-in: point git at the versioned hooks in scripts/hooks (currently only pre-push, which runs check.ps1 -Coverage).
# Undo with: git config --unset core.hooksPath
$Root = Split-Path -Parent $PSScriptRoot
git -C $Root config core.hooksPath scripts/hooks
Write-Host 'Hooks installed: git push now runs scripts\check.ps1 -Coverage first (about 6 minutes). Skip once with --no-verify.' -ForegroundColor Green
