# Toggle e configuracao dos canais de notificacao do Claude Code.
# Plugin: cc-notify-tool
# Efeito instantaneo em todas as instancias rodando (config e lido a cada hook).
#
# Uso:
#   notify-control.ps1                              # status (default)
#   notify-control.ps1 status
#
#   # Toggle por canal
#   notify-control.ps1 on  bell|toast|telegram|all
#   notify-control.ps1 off bell|toast|telegram|all
#   notify-control.ps1 mute                         # = off all
#   notify-control.ps1 unmute                       # = on all
#
#   # Som do bell
#   notify-control.ps1 sound                        # mostra som atual
#   notify-control.ps1 sound list                   # lista wavs do Windows + SystemSounds
#   notify-control.ps1 sound set <nome|caminho>     # define som (ex: "chimes.wav", "Asterisk", "C:/path/x.wav")
#   notify-control.ps1 sound reset                  # volta ao default (SystemSounds.Beep)
#   notify-control.ps1 sound test                   # toca o som atual

param(
    [Parameter(Position = 0)]
    [string]$Action = 'status',

    [Parameter(Position = 1)]
    [string]$Arg1 = '',

    [Parameter(Position = 2)]
    [string]$Arg2 = ''
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $env:USERPROFILE '.claude\notify-config.json'
$mediaDir = 'C:\Windows\Media'
$systemSoundNames = @('Beep', 'Asterisk', 'Exclamation', 'Hand', 'Question')

function Ensure-ConfigDir {
    $dir = Split-Path -Parent $configPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Read-Config {
    $defaults = [ordered]@{
        bell = $true; toast = $true; telegram = $true; bellSound = $null
    }
    if (Test-Path $configPath) {
        try {
            $loaded = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $loaded.channels) {
                if ($null -ne $loaded.channels.bell)     { $defaults.bell     = [bool]$loaded.channels.bell }
                if ($null -ne $loaded.channels.toast)    { $defaults.toast    = [bool]$loaded.channels.toast }
                if ($null -ne $loaded.channels.telegram) { $defaults.telegram = [bool]$loaded.channels.telegram }
            }
            if ($loaded.PSObject.Properties.Name -contains 'bellSound' -and $loaded.bellSound) {
                $defaults.bellSound = [string]$loaded.bellSound
            }
        } catch { }
    }
    return $defaults
}

function Write-Config {
    param([hashtable]$Config)
    Ensure-ConfigDir
    $obj = [ordered]@{
        channels = [ordered]@{
            bell     = $Config.bell
            toast    = $Config.toast
            telegram = $Config.telegram
        }
        bellSound = $Config.bellSound
    }
    $json = $obj | ConvertTo-Json -Depth 5
    Set-Content -Path $configPath -Value $json -Encoding UTF8
}

function Show-Status {
    $c = Read-Config
    $kill = if ($env:CLAUDE_NOTIFY_DISABLED -in @('1', 'true', 'on')) { '  (KILL-SWITCH ATIVO neste terminal)' } else { '' }
    $tgCreds = if ($env:TELEGRAM_BOT_TOKEN -and $env:TELEGRAM_CHAT_ID) { 'creds OK no processo atual' } else { 'sem creds no processo atual' }
    $soundDesc = if ($c.bellSound) { $c.bellSound } else { 'SystemSounds.Beep (default)' }

    Write-Host ''
    Write-Host "Status global ($configPath):$kill"
    Write-Host ('  bell    : {0}   som: {1}' -f $(if ($c.bell) { 'ON' } else { 'OFF' }), $soundDesc)
    Write-Host ('  toast   : {0}' -f $(if ($c.toast) { 'ON' } else { 'OFF' }))
    Write-Host ('  telegram: {0}   ({1})' -f $(if ($c.telegram) { 'ON' } else { 'OFF' }), $tgCreds)
    Write-Host ''
}

function Set-Channels {
    param([string]$Target, [bool]$State)
    if (-not $Target) {
        Write-Error "Canal obrigatorio. Use: bell | toast | telegram | all"
        exit 1
    }
    $valid = @('bell', 'toast', 'telegram', 'all')
    if ($Target -notin $valid) {
        Write-Error "Canal invalido. Use: bell | toast | telegram | all"
        exit 1
    }
    $c = Read-Config
    $list = if ($Target -eq 'all') { @('bell', 'toast', 'telegram') } else { @($Target) }
    foreach ($t in $list) {
        $c[$t] = $State
    }
    Write-Config $c
    Show-Status
}

function Resolve-Sound {
    param([string]$Value)
    if (-not $Value) { return $null }
    if ($Value -in $systemSoundNames) {
        return @{ kind = 'system'; path = $Value }
    }
    $candidate = $Value
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $mediaDir $Value
    }
    if (Test-Path $candidate) {
        return @{ kind = 'file'; path = $candidate }
    }
    return @{ kind = 'unknown'; path = $Value }
}

function Play-Sound {
    param([string]$Value)
    $resolved = Resolve-Sound $Value
    if (-not $resolved) {
        try { [System.Media.SystemSounds]::Beep.Play() } catch { }
        return
    }
    switch ($resolved.kind) {
        'system' {
            $s = [System.Media.SystemSounds]::"$($resolved.path)"
            $s.Play()
        }
        'file' {
            $p = New-Object System.Media.SoundPlayer $resolved.path
            $p.PlaySync()
        }
        default {
            Write-Warning "Som '$Value' nao encontrado. Tocando default."
            [System.Media.SystemSounds]::Beep.Play()
        }
    }
}

function Handle-Sound {
    param([string]$Sub, [string]$Value)
    $c = Read-Config
    switch ($Sub) {
        '' {
            $cur = if ($c.bellSound) { $c.bellSound } else { 'SystemSounds.Beep (default)' }
            Write-Host ''
            Write-Host "Som atual do bell: $cur"
            Write-Host ''
        }
        'list' {
            Write-Host ''
            Write-Host "SystemSounds (mapeados pelo Painel de Som do Windows):"
            $systemSoundNames | ForEach-Object { Write-Host "  $_" }
            Write-Host ''
            Write-Host "Arquivos .wav em C:\Windows\Media:"
            Get-ChildItem (Join-Path $mediaDir '*.wav') -ErrorAction SilentlyContinue |
                Sort-Object Name |
                ForEach-Object { Write-Host "  $($_.Name)" }
            Write-Host ''
            Write-Host "Tambem aceita caminho absoluto para qualquer .wav fora do Windows\Media."
            Write-Host ''
        }
        'set' {
            if (-not $Value) {
                Write-Error "Use: sound set <nome|caminho>"
                exit 1
            }
            $resolved = Resolve-Sound $Value
            if ($resolved.kind -eq 'unknown') {
                Write-Error "Som '$Value' nao encontrado. Use 'sound list' para ver opcoes."
                exit 1
            }
            $c.bellSound = $Value
            Write-Config $c
            Write-Host ''
            Write-Host "Som definido: $Value  ($($resolved.kind): $($resolved.path))"
            Write-Host "Tocando preview..."
            Play-Sound $Value
            Write-Host ''
        }
        'reset' {
            $c.bellSound = $null
            Write-Config $c
            Write-Host ''
            Write-Host "Som resetado para SystemSounds.Beep (default)."
            Write-Host ''
        }
        'test' {
            $current = if ($c.bellSound) { $c.bellSound } else { 'Beep' }
            Write-Host "Tocando: $current"
            Play-Sound $c.bellSound
        }
        default {
            Write-Error "Subcomando invalido. Use: sound [list|set|reset|test]"
            exit 1
        }
    }
}

switch ($Action) {
    'status' { Show-Status }
    'on'     { Set-Channels -Target $Arg1 -State $true }
    'off'    { Set-Channels -Target $Arg1 -State $false }
    'mute'   { Set-Channels -Target 'all' -State $false }
    'unmute' { Set-Channels -Target 'all' -State $true }
    'sound'  { Handle-Sound -Sub $Arg1 -Value $Arg2 }
    default  { Show-Status }
}
