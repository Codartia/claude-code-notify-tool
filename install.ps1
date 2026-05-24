# Pos-install do plugin cc-notify-tool.
# Roda 1x apos /plugin install. Faz:
#  1. Cria ~/.claude/notify-config.json com defaults (se nao existir)
#  2. Patcha ~/.claude/settings.json: preferredNotifChannel = "notifications_disabled"
#  3. Verifica dependencias (pwsh, Windows)
#
# Uso:
#   pwsh -NoProfile -File install.ps1
#
# Idempotente. Pode rodar quantas vezes quiser.

#requires -Version 7.0

param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Info { param($Msg) if (-not $Quiet) { Write-Host "[cc-notify-tool] $Msg" -ForegroundColor Cyan } }
function Warn { param($Msg) Write-Host "[cc-notify-tool] AVISO: $Msg" -ForegroundColor Yellow }
function Ok   { param($Msg) Write-Host "[cc-notify-tool] OK: $Msg" -ForegroundColor Green }

# 1. Verifica plataforma
if (-not $IsWindows -and -not ($PSVersionTable.PSEdition -eq 'Desktop')) {
    Warn "Plataforma nao Windows detectada. Este plugin foi desenhado para Windows + pwsh."
}

# 2. Verifica pwsh
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwsh) {
    Warn "pwsh (PowerShell 7+) nao encontrado no PATH. O hook usa pwsh, nao powershell.exe (5.1)."
    Warn "Instale via: winget install Microsoft.PowerShell"
}

# 3. Diretorio ~/.claude
$claudeDir = Join-Path $env:USERPROFILE '.claude'
if (-not (Test-Path $claudeDir)) {
    Info "Criando $claudeDir"
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

# 4. notify-config.json (default se faltar)
$configPath = Join-Path $claudeDir 'notify-config.json'
if (-not (Test-Path $configPath)) {
    Info "Criando $configPath com defaults (tudo ligado)"
    $defaults = [ordered]@{
        channels  = [ordered]@{ bell = $true; toast = $true; telegram = $true }
        bellSound = $null
    }
    $defaults | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
    Ok "Config criada"
} else {
    Info "Config ja existe em $configPath (preservada)"
}

# 5. Patch settings.json
$settingsPath = Join-Path $claudeDir 'settings.json'
$settings = if (Test-Path $settingsPath) {
    try {
        Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } catch {
        Warn "settings.json existente esta corrompido. Backup em settings.json.bak."
        Copy-Item $settingsPath "$settingsPath.bak"
        @{}
    }
} else {
    @{}
}

$current = $settings['preferredNotifChannel']
if ($current -ne 'notifications_disabled') {
    if ($current) {
        Info "preferredNotifChannel atual: '$current' -> trocando para 'notifications_disabled'"
        Info "(necessario pra evitar beep duplo: o plugin toca o bell via hook)"
    } else {
        Info "Setando preferredNotifChannel = 'notifications_disabled'"
    }
    $settings['preferredNotifChannel'] = 'notifications_disabled'
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
    Ok "settings.json atualizado"
} else {
    Info "settings.json ja tem preferredNotifChannel = 'notifications_disabled'"
}

# 6. Aviso sobre Telegram (opcional)
$tgToken = [Environment]::GetEnvironmentVariable('TELEGRAM_BOT_TOKEN', 'User')
$tgChat  = [Environment]::GetEnvironmentVariable('TELEGRAM_CHAT_ID', 'User')
if (-not $tgToken -or -not $tgChat) {
    Info ""
    Info "Telegram nao configurado (opcional). Para ativar:"
    Info "  1. Crie um bot via @BotFather no Telegram"
    Info "  2. Mande qualquer mensagem pro bot novo"
    Info "  3. Acesse https://api.telegram.org/bot<TOKEN>/getUpdates pra pegar chat.id"
    Info "  4. Persista as creds (escopo User):"
    Info "     [Environment]::SetEnvironmentVariable('TELEGRAM_BOT_TOKEN', '<token>', 'User')"
    Info "     [Environment]::SetEnvironmentVariable('TELEGRAM_CHAT_ID',   '<chat_id>', 'User')"
    Info "  5. Feche e reabra o Claude Code"
}

# 7. Aviso sobre instalacao standalone pre-existente
$hooksDir = Join-Path $claudeDir 'hooks'
if (Test-Path (Join-Path $hooksDir 'notify.ps1')) {
    Warn ""
    Warn "Detectado script standalone em $hooksDir/notify.ps1"
    Warn "Voce pode ter notificacoes duplicadas. Verifique se ~/.claude/settings.json"
    Warn "tem hooks Stop/Notification apontando pra esse arquivo e remova-os manualmente."
}

Ok ""
Ok "Instalacao concluida. Reinicie qualquer instancia ativa do Claude Code pra pegar o hook."
