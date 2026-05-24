# Hook de notificacao multi-canal: Bell + Windows toast + Telegram
# Plugin: cc-notify-tool
# Disparado pelos eventos Stop e Notification do Claude Code.
#
# Controle:
#   - Master kill-switch (por terminal):  $env:CLAUDE_NOTIFY_DISABLED = '1'
#   - Toggle por canal (global, instantaneo): ~/.claude/notify-config.json
#   - Telegram tambem exige TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID nas env vars

$ErrorActionPreference = 'Continue'

# Kill-switch por terminal/processo
if ($env:CLAUDE_NOTIFY_DISABLED -in @('1', 'true', 'on')) {
    exit 0
}

# Le o payload JSON via stdin
try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

# Le config user-mutavel (default: tudo ligado se faltar ou der erro)
$configPath = Join-Path $env:USERPROFILE '.claude\notify-config.json'
$bellOn = $true; $toastOn = $true; $telegramOn = $true
$bellSound = $null
if (Test-Path $configPath) {
    try {
        $loaded = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $loaded.channels) {
            if ($null -ne $loaded.channels.bell)     { $bellOn     = [bool]$loaded.channels.bell }
            if ($null -ne $loaded.channels.toast)    { $toastOn    = [bool]$loaded.channels.toast }
            if ($null -ne $loaded.channels.telegram) { $telegramOn = [bool]$loaded.channels.telegram }
        }
        if ($loaded.PSObject.Properties.Name -contains 'bellSound' -and $loaded.bellSound) {
            $bellSound = [string]$loaded.bellSound
        }
    } catch { }
}

$projectName = if ($payload.cwd) { Split-Path -Leaf $payload.cwd } else { 'unknown' }
$sessionShort = if ($payload.session_id) {
    $payload.session_id.Substring([Math]::Max(0, $payload.session_id.Length - 6))
} else { '?' }
$eventName = $payload.hook_event_name

switch ($eventName) {
    'Stop' {
        $message = 'Processamento concluido - aguardando resposta'
    }
    'Notification' {
        $message = if ($payload.message) { [string]$payload.message } else { 'Atencao necessaria' }
    }
    default {
        $message = "Evento: $eventName"
    }
}

$title = "Claude Code - $projectName"
$subtitle = "$message | sess $sessionShort"

# --- 1. Bell ---
if ($bellOn) {
    $played = $false
    if ($bellSound) {
        if ($bellSound -match '[\\/]' -or $bellSound -match '\.wav$') {
            $resolvedPath = $bellSound
            if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
                $resolvedPath = Join-Path 'C:\Windows\Media' $bellSound
            }
            if (Test-Path $resolvedPath) {
                try {
                    $player = New-Object System.Media.SoundPlayer $resolvedPath
                    $player.Play()
                    $played = $true
                } catch { }
            }
        } else {
            try {
                $sound = [System.Media.SystemSounds]::"$bellSound"
                if ($sound) { $sound.Play(); $played = $true }
            } catch { }
        }
    }
    if (-not $played) {
        try { [System.Media.SystemSounds]::Beep.Play() } catch { }
    }
}

# --- 2. Windows Toast Notification ---
if ($toastOn) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $escTitle = [System.Security.SecurityElement]::Escape($title)
        $escSubtitle = [System.Security.SecurityElement]::Escape($subtitle)

        $xmlContent = @"
<toast><visual><binding template="ToastText02"><text id="1">$escTitle</text><text id="2">$escSubtitle</text></binding></visual></toast>
"@
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlContent)
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show($toast)
    } catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $balloon = New-Object System.Windows.Forms.NotifyIcon
            $balloon.Icon = [System.Drawing.SystemIcons]::Information
            $balloon.BalloonTipTitle = $title
            $balloon.BalloonTipText = $subtitle
            $balloon.Visible = $true
            $balloon.ShowBalloonTip(5000)
            Start-Sleep -Milliseconds 200
        } catch { }
    }
}

# --- 3. Telegram ---
if ($telegramOn -and $env:TELEGRAM_BOT_TOKEN -and $env:TELEGRAM_CHAT_ID) {
    try {
        $telegramText = "*$projectName*`n$message`n_sess $sessionShort_"
        $bodyObj = @{
            chat_id    = $env:TELEGRAM_CHAT_ID
            text       = $telegramText
            parse_mode = 'Markdown'
        }
        $bodyJson = $bodyObj | ConvertTo-Json -Compress
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

        Invoke-RestMethod `
            -Uri "https://api.telegram.org/bot$($env:TELEGRAM_BOT_TOKEN)/sendMessage" `
            -Method Post `
            -ContentType 'application/json; charset=utf-8' `
            -Body $bodyBytes `
            -TimeoutSec 5 | Out-Null
    } catch { }
}

exit 0
