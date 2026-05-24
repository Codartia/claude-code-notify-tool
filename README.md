# cc-notify-tool

Plugin do Claude Code para Windows que dispara notificações multicanal quando uma instância termina o processamento ou precisa de input. Útil quando você roda múltiplas instâncias em paralelo e precisa saber qual delas voltar a interagir.

**Canais:**
- 🔔 **Bell** — som do sistema (customizável: SystemSounds ou `.wav` arbitrário)
- 🪟 **Toast** — notificação nativa do Windows com identificação do projeto
- 📱 **Telegram** — mensagem direto no seu chat (opcional)

Cada notificação identifica a instância pelo nome do projeto (`cwd`) e os últimos 6 chars do `session_id`.

---

## Pré-requisitos

- **Windows 10/11**
- **PowerShell 7+** (`pwsh`) — instale com `winget install Microsoft.PowerShell` se faltar
- **Claude Code** instalado

---

## Instalação

Este repo serve como **marketplace** e como **plugin** ao mesmo tempo (tem `marketplace.json` na raiz). Instalação em 2 passos no Claude Code:

```
/plugin marketplace add Codartia/claude-code-notify-tool
/plugin install cc-notify-tool@codartia
```

Depois, **uma vez**, rode o pós-instalador (configura `preferredNotifChannel` e cria o arquivo de config):

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.claude\plugins\cc-notify-tool\install.ps1"
```

> O caminho exato do plugin pode variar conforme a versão do Claude Code. Se não souber, busque por `cc-notify-tool` em `~/.claude/plugins/`.

Reinicie qualquer instância ativa do Claude Code para o hook entrar em vigor.

---

## Uso

Defina um atalho no seu `$PROFILE` do PowerShell:

```powershell
function notify { & "$env:USERPROFILE\.claude\plugins\cc-notify-tool\scripts\notify-control.ps1" @args }
```

Daí use `notify <comando>`:

```powershell
notify                          # status
notify off telegram             # desliga 1 canal
notify on  toast
notify mute                     # desliga tudo
notify unmute                   # liga tudo

notify sound                    # mostra som atual do bell
notify sound list               # lista opções
notify sound set chimes.wav     # define + preview
notify sound test               # toca o atual
notify sound reset              # volta ao default
```

Toggles têm **efeito instantâneo** em todas as instâncias rodando.

---

## Mute por instância específica

Quer mutar **só uma janela** sem afetar as outras? Setar a env var antes de subir o Claude:

```powershell
$env:CLAUDE_NOTIFY_DISABLED = '1'
claude
```

Essa instância fica muda enquanto viver.

---

## Telegram (opcional)

1. Crie um bot via `@BotFather` no Telegram — receba o **token**.
2. Mande qualquer mensagem pro bot novo.
3. Pegue o `chat.id` em `https://api.telegram.org/bot<TOKEN>/getUpdates`.
4. Persista as credenciais (escopo User):

```powershell
[Environment]::SetEnvironmentVariable('TELEGRAM_BOT_TOKEN', '<token>',   'User')
[Environment]::SetEnvironmentVariable('TELEGRAM_CHAT_ID',   '<chat_id>', 'User')
```

5. **Reinicie** o Claude Code pra ele pegar as env vars.

Verifique com `notify status` — deve mostrar `(creds OK no processo atual)`.

---

## Estrutura

```
cc-notify-tool/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   └── hooks.json              # declara Stop e Notification
├── scripts/
│   ├── notify.ps1              # hook invocado
│   └── notify-control.ps1      # CLI de toggle/som
├── install.ps1                 # pós-install (idempotente)
├── uninstall.ps1               # reverte preferredNotifChannel
└── README.md
```

**Config user-mutável:** `~/.claude/notify-config.json` (criada pelo `install.ps1`, preservada em reinstalações).

---

## Arquitetura

- O `hooks/hooks.json` registra os eventos `Stop` e `Notification` com `${CLAUDE_PLUGIN_ROOT}/scripts/notify.ps1`.
- O hook lê o payload JSON via stdin, extrai `cwd`, `session_id` e `message`.
- Lê toggles e som do `~/.claude/notify-config.json` em cada invocação (efeito instantâneo).
- Bell: `[System.Media.SystemSounds]` ou `System.Media.SoundPlayer` para `.wav`.
- Toast: WinRT `ToastNotification` com fallback para `NotifyIcon` balloon.
- Telegram: `POST https://api.telegram.org/bot<token>/sendMessage` se as env vars estiverem definidas.

---

## Troubleshooting

**Hook não dispara**
- Confira: `Get-Command pwsh` deve retornar `C:\Program Files\PowerShell\7\pwsh.exe`.
- Teste manual:
  ```powershell
  '{"session_id":"test","cwd":"F:/foo","hook_event_name":"Stop"}' | pwsh -NoProfile -File "$env:USERPROFILE\.claude\plugins\cc-notify-tool\scripts\notify.ps1"
  ```
- Verifique que `/plugin list` mostra `cc-notify-tool`.

**Beep duplo**
- `preferredNotifChannel` em `~/.claude/settings.json` voltou pra `terminal_bell`. Rode `install.ps1` de novo.

**Telegram não chega**
- `notify status` mostra "sem creds no processo atual" — reinicie aquela instância do Claude.
- Teste creds: `Invoke-RestMethod "https://api.telegram.org/bot$env:TELEGRAM_BOT_TOKEN/getMe"`

**Toast não aparece**
- Verifique notificações habilitadas pro app "Claude Code" em Configurações > Sistema > Notificações.
- O script tem fallback pra `NotifyIcon` se WinRT falhar.

---

## Desinstalar

```
/plugin uninstall cc-notify-tool@codartia
/plugin marketplace remove codartia
```

Reverter as mudanças no `settings.json`:

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.claude\plugins\cc-notify-tool\uninstall.ps1"
# Adicione -Purge pra apagar tambem o ~/.claude/notify-config.json
```

---

## Adicionando novos canais (Slack, Discord, ntfy...)

1. Em `scripts/notify.ps1`: ler flag do `notify-config.json` (`$channels.meu_canal`), checar creds em env vars, falhar silenciosamente se faltar.
2. Em `scripts/notify-control.ps1`: incluir `meu_canal` na lista de canais válidos.
3. Default = ligado quando ausente do config.
4. Incluir nome do projeto + `sess <id>` na mensagem.

---

## Eventos cobertos

| Evento | Quando dispara | Mensagem |
|---|---|---|
| `Stop` | Claude terminou a resposta | "Processamento concluido - aguardando resposta" |
| `Notification` | Claude pede input/permissão | usa `payload.message` |

Pra cobrir mais eventos (`SubagentStop`, etc.), edite `hooks/hooks.json` apontando pro mesmo `notify.ps1`.

---

## Licença

MIT — veja [LICENSE](LICENSE).
