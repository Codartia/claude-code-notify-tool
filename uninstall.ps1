# Uninstall do plugin cc-notify-tool.
# Reverte preferredNotifChannel para o default ("auto") em ~/.claude/settings.json.
# Nao apaga o ~/.claude/notify-config.json (preserva preferencias).
#
# Uso:
#   pwsh -NoProfile -File uninstall.ps1
#   pwsh -NoProfile -File uninstall.ps1 -Purge   # apaga config tambem

#requires -Version 7.0

param(
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

function Info { param($Msg) Write-Host "[cc-notify-tool] $Msg" -ForegroundColor Cyan }
function Ok   { param($Msg) Write-Host "[cc-notify-tool] OK: $Msg" -ForegroundColor Green }

$claudeDir = Join-Path $env:USERPROFILE '.claude'
$settingsPath = Join-Path $claudeDir 'settings.json'

if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if ($settings['preferredNotifChannel'] -eq 'notifications_disabled') {
        Info "Revertendo preferredNotifChannel para 'auto'"
        $settings['preferredNotifChannel'] = 'auto'
        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
        Ok "settings.json atualizado"
    }
}

if ($Purge) {
    $configPath = Join-Path $claudeDir 'notify-config.json'
    if (Test-Path $configPath) {
        Info "Removendo $configPath"
        Remove-Item $configPath -Force
        Ok "Config removida"
    }
}

Ok ""
Ok "Para remover totalmente: rode '/plugin uninstall cc-notify-tool' no Claude Code."
