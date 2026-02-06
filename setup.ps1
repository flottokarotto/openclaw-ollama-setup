# OpenClaw + Ollama Setup Script for Windows
# Prerequisites: Docker Desktop running, Ollama installed

$ErrorActionPreference = "Stop"

# --- Configuration ---
$OLLAMA_MODEL = "qwen3:14b"

# --- Telegram Channel (optional) ---
# Override these in run-telegram.ps1 or set before dot-sourcing
if ($null -eq $SETUP_TELEGRAM)    { $SETUP_TELEGRAM = $false }     # Set to $true to enable Telegram
if (-not $TELEGRAM_BOT_TOKEN)     { $TELEGRAM_BOT_TOKEN = "" }     # Token from @BotFather
if (-not $TELEGRAM_ALLOW_FROM)    { $TELEGRAM_ALLOW_FROM = @() }   # Allowed user IDs, e.g. @("123456789")

# Generate cryptographically secure token (CSPRNG)
$tokenBytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($tokenBytes)
$GATEWAY_TOKEN = [BitConverter]::ToString($tokenBytes).Replace("-", "").ToLower()
$CONFIG_DIR = "$env:USERPROFILE\.openclaw"
$WORKSPACE_DIR = "$CONFIG_DIR\workspace"
$OPENCLAW_REPO = "$env:USERPROFILE\workspace\openclaw\openclaw"

# --- Detect Ollama installation ---
$OLLAMA_EXE = $null
$ollamaInPath = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollamaInPath) {
    $OLLAMA_EXE = $ollamaInPath.Source
} else {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:ProgramFiles\Ollama\ollama.exe",
        "$env:ProgramFiles(x86)\Ollama\ollama.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            $OLLAMA_EXE = $candidate
            break
        }
    }
}
if (-not $OLLAMA_EXE) {
    Write-Host "ERROR: Ollama not found. Please install it or check the path." -ForegroundColor Red
    exit 1
}
Write-Host "Ollama found: $OLLAMA_EXE" -ForegroundColor Gray

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " OpenClaw + Ollama Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($SETUP_TELEGRAM) {
    Write-Host "Telegram channel enabled" -ForegroundColor Gray
}

$totalSteps = 7

# --- 1. Check if Docker is running ---
Write-Host "`n[1/$totalSteps] Checking Docker..." -ForegroundColor Yellow
try {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker info 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) { throw "Docker not reachable" }
} catch {
    $ErrorActionPreference = $prevEAP
    Write-Host "ERROR: Docker is not running. Start Docker Desktop first." -ForegroundColor Red
    exit 1
}
Write-Host "  OK" -ForegroundColor Green

# --- 2. Check if Ollama is running and pull model ---
Write-Host "`n[2/$totalSteps] Checking Ollama and pulling model '$OLLAMA_MODEL'..." -ForegroundColor Yellow
try {
    $tagsResponse = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5
    $ollamaModels = ($tagsResponse.Content | ConvertFrom-Json).models.name
} catch {
    Write-Host "ERROR: Ollama is not running (API at localhost:11434 not reachable)." -ForegroundColor Red
    Write-Host "  Start Ollama first: & '$OLLAMA_EXE' serve" -ForegroundColor Yellow
    exit 1
}

# Pull model if not available
if ($ollamaModels -notcontains $OLLAMA_MODEL) {
    Write-Host "  Downloading model (this may take a while)..." -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $OLLAMA_EXE pull $OLLAMA_MODEL 2>&1
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to download model." -ForegroundColor Red
        exit 1
    }
}
Write-Host "  OK - Model '$OLLAMA_MODEL' available" -ForegroundColor Green

# --- 3. Verify Ollama is reachable (no 0.0.0.0 binding needed) ---
# Docker Desktop for Windows routes host.docker.internal to the host's
# localhost, so Ollama can stay on its default 127.0.0.1 binding.
Write-Host "`n[3/$totalSteps] Verifying Ollama connectivity..." -ForegroundColor Yellow
Write-Host "  OK - Docker Desktop routes to Ollama via host.docker.internal" -ForegroundColor Green
Write-Host "  No need to change Ollama's default binding." -ForegroundColor Gray

# --- 4. Create config directories ---
Write-Host "`n[4/$totalSteps] Creating config directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $CONFIG_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $WORKSPACE_DIR | Out-Null
New-Item -ItemType Directory -Force -Path "$CONFIG_DIR\canvas" | Out-Null
Write-Host "  OK - $CONFIG_DIR" -ForegroundColor Green

# --- 5. Write openclaw.json ---
Write-Host "`n[5/$totalSteps] Writing openclaw.json..." -ForegroundColor Yellow

$config = @"
{
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "agents": {
    "defaults": {
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      },
      "compaction": {
        "mode": "safeguard"
      },
      "workspace": "/home/node/.openclaw/workspace",
      "model": {
        "primary": "ollama/$OLLAMA_MODEL"
      },
      "models": {
        "ollama/$OLLAMA_MODEL": {
          "alias": "Local Ollama"
        }
      }
    }
  },
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "http://host.docker.internal:11434/v1",
        "apiKey": "ollama-local",
        "api": "openai-completions",
        "models": [
          {
            "id": "$OLLAMA_MODEL",
            "name": "Local Ollama",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 131072,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    },
    "port": 18789,
    "bind": "lan",
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "channels": "__TELEGRAM_CHANNEL__",
  "plugins": {},
  "skills": {
    "install": {
      "nodeManager": "npm"
    }
  },
  "meta": {
    "lastTouchedVersion": "2026.2.4",
    "lastTouchedAt": "$(Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")"
  }
}
"@

# Build channels config
if ($SETUP_TELEGRAM -and $TELEGRAM_BOT_TOKEN) {
    $allowFromJson = ($TELEGRAM_ALLOW_FROM | ForEach-Object { "`"$_`"" }) -join ", "
    $telegramChannelJson = @"
{
    "telegram": {
      "enabled": true,
      "botToken": "$TELEGRAM_BOT_TOKEN",
      "dmPolicy": "allowlist",
      "allowFrom": [$allowFromJson]
    }
  }
"@
    $config = $config.Replace('"__TELEGRAM_CHANNEL__"', $telegramChannelJson)
} else {
    $config = $config.Replace('"__TELEGRAM_CHANNEL__"', '{}')
}

$config | Out-File -FilePath "$CONFIG_DIR\openclaw.json" -Encoding utf8
Write-Host "  OK" -ForegroundColor Green

# --- 6. Build Docker image ---
Write-Host "`n[6/$totalSteps] Building Docker image..." -ForegroundColor Yellow

if (Test-Path "$OPENCLAW_REPO\Dockerfile") {
    Write-Host "  Building image from repo (may take several minutes)..." -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker build -t openclaw:local -f "$OPENCLAW_REPO\Dockerfile" $OPENCLAW_REPO 2>&1
    $buildExitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($buildExitCode -ne 0) {
        Write-Host "ERROR: Failed to build Docker image." -ForegroundColor Red
        exit 1
    }
    Write-Host "  OK - Image 'openclaw:local' built" -ForegroundColor Green
} else {
    Write-Host "  No Dockerfile in repo - using community image" -ForegroundColor Yellow
}

# --- 7. Start Docker container ---
Write-Host "`n[7/$totalSteps] Starting OpenClaw container..." -ForegroundColor Yellow

# Stop old container if present
try { docker stop openclaw 2>&1 | Out-Null } catch {}
try { docker rm openclaw 2>&1 | Out-Null } catch {}

if (Test-Path "$OPENCLAW_REPO\docker-compose.yml") {
    Write-Host "  Using docker-compose from repo..." -ForegroundColor Yellow

    # Set environment variables for docker-compose
    $env:OPENCLAW_CONFIG_DIR = $CONFIG_DIR
    $env:OPENCLAW_WORKSPACE_DIR = $WORKSPACE_DIR
    $env:OPENCLAW_GATEWAY_TOKEN = $GATEWAY_TOKEN
    $env:OPENCLAW_IMAGE = "openclaw:local"
    # Bind Docker ports to 127.0.0.1 only (not LAN-accessible from host)
    $env:OPENCLAW_GATEWAY_PORT = "127.0.0.1:18789"
    $env:OPENCLAW_BRIDGE_PORT = "127.0.0.1:18790"
    # Gateway listens on lan inside the container (needed for Docker port forwarding)
    $env:OPENCLAW_GATEWAY_BIND = "lan"
    # Optional session keys (not needed for Ollama-only setup)
    if (-not $env:CLAUDE_AI_SESSION_KEY) { $env:CLAUDE_AI_SESSION_KEY = "" }
    if (-not $env:CLAUDE_WEB_SESSION_KEY) { $env:CLAUDE_WEB_SESSION_KEY = "" }
    if (-not $env:CLAUDE_WEB_COOKIE) { $env:CLAUDE_WEB_COOKIE = "" }

    # Create .env file for docker-compose
    $envContent = @"
OPENCLAW_CONFIG_DIR=$CONFIG_DIR
OPENCLAW_WORKSPACE_DIR=$WORKSPACE_DIR
OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
OPENCLAW_IMAGE=openclaw:local
OPENCLAW_GATEWAY_PORT=127.0.0.1:18789
OPENCLAW_BRIDGE_PORT=127.0.0.1:18790
OPENCLAW_GATEWAY_BIND=lan
CLAUDE_AI_SESSION_KEY=
CLAUDE_WEB_SESSION_KEY=
CLAUDE_WEB_COOKIE=
"@
    $envContent | Out-File -FilePath "$OPENCLAW_REPO\.env" -Encoding ascii -NoNewline

    Push-Location $OPENCLAW_REPO
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker compose down 2>&1 | Out-Null
    docker compose up -d openclaw-gateway 2>&1
    $ErrorActionPreference = $prevEAP
    Pop-Location
} else {
    # Fallback: run community image directly
    Write-Host "  Using community image ghcr.io/phioranex/openclaw-docker..." -ForegroundColor Yellow
    docker run -d `
        --name openclaw `
        --restart unless-stopped `
        -v "${CONFIG_DIR}:/home/node/.openclaw" `
        -v "${WORKSPACE_DIR}:/home/node/.openclaw/workspace" `
        -p 127.0.0.1:18789:18789 `
        -e "OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN" `
        ghcr.io/phioranex/openclaw-docker:latest `
        gateway start --foreground
}

Start-Sleep -Seconds 3

# --- Done ---
Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Dashboard URL:" -ForegroundColor Cyan
Write-Host "  http://127.0.0.1:18789/?token=$GATEWAY_TOKEN" -ForegroundColor White
Write-Host ""
Write-Host "Token (save for later):" -ForegroundColor Cyan
Write-Host "  $GATEWAY_TOKEN" -ForegroundColor White
Write-Host ""
Write-Host "Model: $OLLAMA_MODEL" -ForegroundColor Cyan
Write-Host "Config: $CONFIG_DIR\openclaw.json" -ForegroundColor Cyan
Write-Host ""
Write-Host "View logs:" -ForegroundColor Cyan
Write-Host "  docker compose -f $OPENCLAW_REPO\docker-compose.yml logs -f openclaw-gateway" -ForegroundColor White
Write-Host "  (or: docker logs -f openclaw)" -ForegroundColor Gray
Write-Host ""

if ($SETUP_TELEGRAM) {
    Write-Host "Telegram Bot:" -ForegroundColor Cyan
    Write-Host "  Send a message to your bot in Telegram to start chatting." -ForegroundColor White
    Write-Host ""
}

# Copy URL to clipboard
try {
    "http://127.0.0.1:18789/?token=$GATEWAY_TOKEN" | Set-Clipboard
    Write-Host "(Dashboard URL copied to clipboard)" -ForegroundColor Gray
} catch {}
