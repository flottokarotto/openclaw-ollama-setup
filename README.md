# OpenClaw + Ollama Setup

One-script setup to run [OpenClaw](https://github.com/openclaw/openclaw) with a local [Ollama](https://ollama.com) model on Windows. No cloud API keys needed -- everything runs on your machine.

## What it does

The `setup.ps1` script automates the entire setup process:

1. Detects Ollama installation (auto-starts if not running)
2. Pulls all configured models
3. Verifies Docker Desktop and Ollama connectivity
4. Creates config directories (including `skills/`) and copies workspace templates (`AGENTS.md`)
5. Writes `openclaw.json` with model config, aliases, and optional channels/tools
6. Builds the OpenClaw Docker image from source (cached -- skips if unchanged)
7. Starts the gateway container via Docker Compose and runs a health check

The gateway token is persisted across runs, so your dashboard URL stays the same.

## Prerequisites

| Requirement | Notes |
|---|---|
| **Windows 10/11** | PowerShell 5.1+ |
| **Docker Desktop** | Must be running before setup |
| **Ollama** | [Download](https://ollama.com/download) -- script auto-starts it if needed |
| **OpenClaw repo** | Included as git submodule |

## Quick Start

```powershell
# 1. Clone this repo (with submodule)
git clone --recurse-submodules https://github.com/flottokarotto/openclaw-ollama-setup.git ~/workspace/openclaw
cd ~/workspace/openclaw

# If already cloned without --recurse-submodules:
# git submodule update --init

# 2. Make sure Docker Desktop is running

# 3. Run setup (Ollama is auto-started if needed)
.\setup.ps1
```

After setup completes, open the dashboard URL printed in the terminal. On first connect, approve the device pairing:

```powershell
docker exec openclaw-openclaw-gateway-1 node dist/index.js devices list
docker exec openclaw-openclaw-gateway-1 node dist/index.js devices approve <requestId>
```

## Configuration

Edit the variables at the top of `setup.ps1` or override them in a wrapper script:

| Variable | Default | Description |
|---|---|---|
| `$OLLAMA_MODELS` | `@("qwen3:14b")` | Ollama models (first = primary, last = subagents) |
| `$SETUP_TELEGRAM` | `$false` | Enable Telegram channel |
| `$TELEGRAM_BOT_TOKEN` | `""` | Bot token from @BotFather |
| `$TELEGRAM_ALLOW_FROM` | `@()` | Allowed Telegram user IDs (DMs) |
| `$TELEGRAM_GROUP_ALLOW` | `@()` | Allowed Telegram group IDs |
| `$BRAVE_SEARCH_API_KEY` | `""` | Brave Search API key for web search |
| `$SETUP_GITHUB` | `$false` | Install GitHub CLI (`gh`) in the container |
| `$GITHUB_TOKEN` | `""` | GitHub personal access token for `gh` |
| `$AUTO_UPDATE` | `$false` | Pull latest OpenClaw source before building |
| `$INTERACTIVE_MODEL_SELECT` | `$false` | Show model picker during setup |

### Multiple models and aliases

By default, a single model is registered:
- **`qwen3:14b`** — primary model (alias: `smart`), used for conversations and subagents

For a dual-model setup with a faster subagent model:

```powershell
$OLLAMA_MODELS = @("qwen3:14b", "qwen3:8b")
```

Switch models in chat with `/model smart` or `/model fast`. Subagents (parallel helper tasks) always use the last model in the list.

Register additional models:

```powershell
$OLLAMA_MODELS = @("qwen3:14b", "qwen3:8b", "mistral:7b")
.\setup.ps1
```

All models are pulled automatically. The first model is the primary, the last is used for subagents.

### Interactive model selection

Set `$INTERACTIVE_MODEL_SELECT = $true` to pick from your installed Ollama models during setup:

```powershell
$INTERACTIVE_MODEL_SELECT = $true
.\setup.ps1
```

### Supported models

Any model available in Ollama works. Popular choices:

| Model | Size | RAM needed |
|---|---|---|
| `qwen3:14b` | 9.3 GB | ~12 GB |
| `llama3.1:8b` | 4.7 GB | ~8 GB |
| `mistral:7b` | 4.1 GB | ~8 GB |
| `gemma2:9b` | 5.4 GB | ~10 GB |
| `qwen3:32b` | 20 GB | ~24 GB |

### Auto-update

Set `$AUTO_UPDATE = $true` to pull the latest OpenClaw source before building. The image cache detects the change and rebuilds automatically.

```powershell
$AUTO_UPDATE = $true
.\setup.ps1
```

## Brave Search (optional)

Give OpenClaw the ability to search the web. Get a free API key (2,000 queries/month) from [brave.com/search/api](https://brave.com/search/api).

```powershell
$BRAVE_SEARCH_API_KEY = "BSA..."
.\setup.ps1
```

Or add it to your wrapper script (e.g. `run-telegram.ps1`).

## GitHub (optional)

Install the GitHub CLI (`gh`) in the container so OpenClaw can interact with repositories, issues, and pull requests.

```powershell
$SETUP_GITHUB = $true
$GITHUB_TOKEN = "ghp_..."    # Personal access token from github.com/settings/tokens
.\setup.ps1
```

This adds `gh` to the Docker image via `OPENCLAW_DOCKER_APT_PACKAGES` (triggers a one-time rebuild). The token is passed as `GH_TOKEN` environment variable.

## Telegram Channel (optional)

Connect OpenClaw to Telegram so you can chat with it from your phone.

### Setup

1. Open Telegram, message **@BotFather**, send `/newbot`, and follow the prompts
2. Copy the bot token (looks like `123456:ABC-DEF...`)
3. Create `run-telegram.ps1` (gitignored) with your token:
   ```powershell
   $SETUP_TELEGRAM = $true
   $TELEGRAM_BOT_TOKEN = "123456:ABC-DEF..."
   $TELEGRAM_ALLOW_FROM = @("your_user_id")
   . "$PSScriptRoot\setup.ps1"
   ```
4. Run `.\run-telegram.ps1`
5. Send a message to your bot in Telegram

To find your Telegram user ID, message **@userinfobot** or check the gateway logs after sending a message to your bot.

### Group chats

Complete guide to get the bot working in Telegram groups -- reading and responding to all messages without @mention.

#### 1. BotFather settings

Message **@BotFather** in Telegram:

1. `/mybots` -> select your bot -> **Bot Settings** -> **Group Privacy** -> **Turn off**
2. `/mybots` -> select your bot -> **Bot Settings** -> **Allow Groups?** -> make sure groups are allowed

Verify the settings stuck:

```
/mybots -> select your bot -> Bot Settings -> Group Privacy
```

It should say "Privacy mode is disabled". If it still says enabled, toggle it again.

#### 2. Add the bot to the group

1. Open your Telegram group -> Add member -> search for your bot -> add it
2. **If you changed Privacy Mode after the bot was already in the group:** remove the bot from the group and add it again. Telegram only applies privacy mode changes on rejoin.

#### 3. Setup script config

In your `run-telegram.ps1`, add the group ID:

```powershell
$SETUP_TELEGRAM = $true
$TELEGRAM_BOT_TOKEN = "123456:ABC-DEF..."
$TELEGRAM_ALLOW_FROM = @("your_user_id")
$TELEGRAM_GROUP_ALLOW = @("-1001234567890")
. "$PSScriptRoot\setup.ps1"
```

This generates the following config in `openclaw.json`:
- `groupPolicy: "open"` -- accepts messages from all groups
- `groups.<chatId>.requireMention: false` -- responds to all messages, not just @mentions
- `ackReactionScope: "all"` -- sends read reactions on all messages

#### 4. Find the group chat ID

Group chat IDs are **negative numbers** (e.g. `-1001234567890`). To find yours:

1. Add the bot to the group
2. Send a message in the group
3. Check the gateway logs:
   ```powershell
   docker compose -f openclaw/docker-compose.yml logs -f openclaw-gateway
   ```
4. Look for the `chat.id` value in the log output

Alternatively, add **@userinfobot** to the group temporarily -- it will print the group ID.

#### 5. Verify

After setup, check that the bot can see messages:

```powershell
# Check bot settings via Telegram API
docker exec openclaw-openclaw-gateway-1 node -e "
  fetch('https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getMe')
    .then(r => r.json()).then(d => console.log(JSON.stringify(d.result, null, 2)))
"
```

`can_read_all_group_messages` must be `true`. If it's `false`, repeat step 1 and re-add the bot to the group.

#### Troubleshooting groups

| Problem | Cause | Fix |
|---|---|---|
| Bot doesn't see group messages | Privacy Mode still on | Disable in BotFather, remove + re-add bot |
| Bot only responds to you | Other members not sending to the right group | Verify group chat ID in config |
| `chat not found` errors | Missing minus in chat ID | Group IDs are negative, e.g. `-1001234567890` |
| Bot echoes/loops | AGENTS.md too large or model finetune issue | Keep AGENTS.md under ~1K chars, use stock `qwen3:14b` |

## Workspace Templates

The `workspace-template/` directory contains files that are copied to the OpenClaw workspace on first run (existing files are not overwritten):

- **`AGENTS.md`** -- Agent instructions (system prompt). Kept small (~900 chars) to stay within local LLM context limits. Includes memory conventions, safety rules, content policy, group chat behavior, and skill/subagent instructions.

To customize the agent's behavior, edit `~/.openclaw/workspace/AGENTS.md` after setup. The template is only copied if the file doesn't already exist.

### Skills

The setup creates a `~/.openclaw/skills/` directory for custom skills. The bot can create new skills via the built-in `skill-creator` skill, or you can add them manually.

## Architecture

```
  +----------+    +----------+
  | Browser  |    | Telegram |
  | (Dashboard)   | Bot      |
  +----+-----+    +----+-----+
       |               |
       +-------+-------+
               |
               | WebSocket :18789
               |
      +--------+---------+          +------------------+
      |   OpenClaw       |--gh----->|    GitHub API     |
      |   Gateway        |          +------------------+
      |   (Docker)       |          +------------------+
      |                  |--search->|  Brave Search    |
      +--------+---------+          +------------------+
               |
               | OpenAI-compat API
               | host.docker.internal:11434
               |
      +--------+---------+
      |    Ollama        |
      |    (Host)        |
      +------------------+
```

## Troubleshooting

### Ollama not found

The script auto-detects Ollama in common locations:
- `%LOCALAPPDATA%\Programs\Ollama\ollama.exe`
- `%ProgramFiles%\Ollama\ollama.exe`

If installed elsewhere, add it to your PATH or edit the `$candidates` array in the script.

### Docker can't reach Ollama

Docker Desktop for Windows routes `host.docker.internal` to the host's localhost automatically, so Ollama works with its default `127.0.0.1` binding. Make sure Ollama is running (`ollama serve`) and check the container logs for connection errors.

### Gateway config invalid

OpenClaw's `gateway.bind` only accepts: `loopback`, `lan`, `tailnet`, `auto`, `custom` -- not raw IPs.

### Bot echoes messages or enters infinite loop

The system prompt (`AGENTS.md`) may be too large for the model's context. Keep it under ~1K chars for 14B models. The default template in `workspace-template/` is already optimized for this. If you customized `AGENTS.md`, try trimming it.

Some finetunes (e.g. JOSIEFIED-Qwen3) can cause tool-call loops. Switch to the stock model (`qwen3:14b`).

### Bot doesn't respond in Telegram groups

1. Privacy Mode must be **off** (see Telegram > Group chats above)
2. Bot must be **removed and re-added** after changing privacy mode
3. Group chat IDs are negative (e.g. `-1001234567890`)
4. Small models (4B) may drop the minus from chat IDs, causing `chat not found` errors -- use 14B+

### Container keeps restarting

Check logs:
```powershell
docker logs openclaw-openclaw-gateway-1
```

### "pairing required" in dashboard

Approve the browser as a trusted device:
```powershell
docker exec openclaw-openclaw-gateway-1 node dist/index.js devices list
docker exec openclaw-openclaw-gateway-1 node dist/index.js devices approve <requestId>
```

## Useful Commands

```powershell
# Quick restart (no rebuild)
.\restart.ps1

# View gateway logs
docker compose -f openclaw/docker-compose.yml logs -f openclaw-gateway

# Send a test message
docker exec openclaw-openclaw-gateway-1 node dist/index.js agent --message "Hello!" --local --agent main

# Check gateway health
docker exec openclaw-openclaw-gateway-1 node dist/index.js health

# List agents
docker exec openclaw-openclaw-gateway-1 node dist/index.js agents list

# Stop everything
docker compose -f openclaw/docker-compose.yml down
```

## Security

- **Ports bound to localhost only** -- Docker maps ports to `127.0.0.1` on the host, so the dashboard is not reachable from the LAN. The gateway uses `bind: lan` inside the container (required for Docker port forwarding to work).
- **Token is generated with CSPRNG** -- uses `System.Security.Cryptography.RandomNumberGenerator`, not `Get-Random`. Token is persisted across runs.
- **Device pairing required** -- new browsers must be explicitly approved before they can connect.
- **Ollama stays on localhost** -- Docker Desktop routes `host.docker.internal` to the host's `127.0.0.1`, so Ollama does not need to bind to `0.0.0.0` and is not exposed to the LAN.

## License

[MIT](LICENSE)
