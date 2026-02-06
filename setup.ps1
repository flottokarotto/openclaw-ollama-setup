# OpenClaw + Ollama Setup Script for Windows
# Voraussetzungen: Docker Desktop laeuft, Ollama installiert

$ErrorActionPreference = "Stop"

# --- Konfiguration ---
$OLLAMA_MODEL = "qwen3:14b"
# Kryptografisch sicheren Token generieren (CSPRNG)
$tokenBytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($tokenBytes)
$GATEWAY_TOKEN = [BitConverter]::ToString($tokenBytes).Replace("-", "").ToLower()
$CONFIG_DIR = "$env:USERPROFILE\.openclaw"
$WORKSPACE_DIR = "$CONFIG_DIR\workspace"
$OPENCLAW_REPO = "$env:USERPROFILE\workspace\openclaw\openclaw"

# --- Ollama-Pfad ermitteln ---
$OLLAMA_EXE = $null
# Zuerst im PATH suchen
$ollamaInPath = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollamaInPath) {
    $OLLAMA_EXE = $ollamaInPath.Source
} else {
    # Standard-Installationspfade pruefen
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
    Write-Host "FEHLER: Ollama nicht gefunden. Bitte installieren oder Pfad pruefen." -ForegroundColor Red
    exit 1
}
Write-Host "Ollama gefunden: $OLLAMA_EXE" -ForegroundColor Gray

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " OpenClaw + Ollama Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# --- 1. Pruefen ob Docker laeuft ---
Write-Host "`n[1/7] Pruefe Docker..." -ForegroundColor Yellow
try {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker info 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) { throw "Docker nicht erreichbar" }
} catch {
    $ErrorActionPreference = $prevEAP
    Write-Host "FEHLER: Docker laeuft nicht. Starte Docker Desktop zuerst." -ForegroundColor Red
    exit 1
}
Write-Host "  OK" -ForegroundColor Green

# --- 2. Pruefen ob Ollama laeuft und Model pullen ---
Write-Host "`n[2/7] Pruefe Ollama und pull Model '$OLLAMA_MODEL'..." -ForegroundColor Yellow
try {
    # Ollama API direkt pruefen (PATH-unabhaengig)
    $tagsResponse = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5
    $ollamaModels = ($tagsResponse.Content | ConvertFrom-Json).models.name
} catch {
    Write-Host "FEHLER: Ollama laeuft nicht (API auf localhost:11434 nicht erreichbar)." -ForegroundColor Red
    Write-Host "  Starte Ollama zuerst: & '$OLLAMA_EXE' serve" -ForegroundColor Yellow
    exit 1
}

# Model pullen falls nicht vorhanden
if ($ollamaModels -notcontains $OLLAMA_MODEL) {
    Write-Host "  Model wird heruntergeladen (kann dauern)..." -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $OLLAMA_EXE pull $OLLAMA_MODEL 2>&1
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FEHLER: Model konnte nicht geladen werden." -ForegroundColor Red
        exit 1
    }
}
Write-Host "  OK - Model '$OLLAMA_MODEL' verfuegbar" -ForegroundColor Green

# --- 3. Pruefen ob Ollama fuer Docker erreichbar ist ---
Write-Host "`n[3/7] Pruefe Ollama Docker-Zugriff..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5
    Write-Host "  OK - Ollama API erreichbar auf localhost:11434" -ForegroundColor Green
} catch {
    Write-Host "  WARNUNG: Ollama API nicht erreichbar auf localhost:11434" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  SICHERHEITSHINWEIS:" -ForegroundColor Red
Write-Host "  Ollama muss auf 0.0.0.0 lauschen, damit Docker darauf zugreifen kann." -ForegroundColor Yellow
Write-Host "  Das bedeutet: Ollama ist im gesamten LAN ohne Passwort erreichbar!" -ForegroundColor Yellow
Write-Host "  Empfehlung: Windows-Firewall Regel erstellen, die Port 11434" -ForegroundColor Yellow
Write-Host "  nur fuer lokale Verbindungen erlaubt:" -ForegroundColor Yellow
Write-Host "    New-NetFirewallRule -DisplayName 'Ollama - Block LAN' ``" -ForegroundColor White
Write-Host "      -Direction Inbound -LocalPort 11434 -Protocol TCP ``" -ForegroundColor White
Write-Host "      -RemoteAddress LocalSubnet -Action Block" -ForegroundColor White
Write-Host ""
Write-Host "  Falls noetig, Ollama neu starten mit:" -ForegroundColor Yellow
Write-Host "    `$env:OLLAMA_HOST='0.0.0.0:11434'; & '$OLLAMA_EXE' serve" -ForegroundColor White

# --- 4. Config-Verzeichnisse erstellen ---
Write-Host "`n[4/7] Erstelle Config-Verzeichnisse..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $CONFIG_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $WORKSPACE_DIR | Out-Null
New-Item -ItemType Directory -Force -Path "$CONFIG_DIR\canvas" | Out-Null
Write-Host "  OK - $CONFIG_DIR" -ForegroundColor Green

# --- 5. openclaw.json schreiben ---
Write-Host "`n[5/7] Schreibe openclaw.json..." -ForegroundColor Yellow

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
            "contextWindow": 32768,
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
    "bind": "loopback",
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "channels": {},
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

$config | Out-File -FilePath "$CONFIG_DIR\openclaw.json" -Encoding utf8
Write-Host "  OK" -ForegroundColor Green

# --- 6. Docker Image bauen ---
Write-Host "`n[6/7] Baue Docker Image..." -ForegroundColor Yellow

# Pruefe ob Repo mit Dockerfile vorhanden ist
if (Test-Path "$OPENCLAW_REPO\Dockerfile") {
    Write-Host "  Baue Image aus Repo (kann einige Minuten dauern)..." -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker build -t openclaw:local -f "$OPENCLAW_REPO\Dockerfile" $OPENCLAW_REPO 2>&1
    $buildExitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($buildExitCode -ne 0) {
        Write-Host "FEHLER: Docker Image konnte nicht gebaut werden." -ForegroundColor Red
        exit 1
    }
    Write-Host "  OK - Image 'openclaw:local' gebaut" -ForegroundColor Green
} else {
    Write-Host "  Kein Dockerfile im Repo - nutze Community-Image" -ForegroundColor Yellow
}

# --- 7. Docker Container starten ---
Write-Host "`n[7/7] Starte OpenClaw Container..." -ForegroundColor Yellow

# Alten Container stoppen falls vorhanden
try { docker stop openclaw 2>&1 | Out-Null } catch {}
try { docker rm openclaw 2>&1 | Out-Null } catch {}

# Pruefe ob Repo mit docker-compose vorhanden ist
if (Test-Path "$OPENCLAW_REPO\docker-compose.yml") {
    Write-Host "  Nutze docker-compose aus Repo..." -ForegroundColor Yellow

    # Environment-Variablen fuer docker-compose setzen
    $env:OPENCLAW_CONFIG_DIR = $CONFIG_DIR
    $env:OPENCLAW_WORKSPACE_DIR = $WORKSPACE_DIR
    $env:OPENCLAW_GATEWAY_TOKEN = $GATEWAY_TOKEN
    $env:OPENCLAW_IMAGE = "openclaw:local"
    $env:OPENCLAW_GATEWAY_PORT = "18789"
    $env:OPENCLAW_BRIDGE_PORT = "18790"
    $env:OPENCLAW_GATEWAY_BIND = "loopback"
    # Optionale Session-Keys (nicht benoetigt fuer Ollama-only Setup)
    if (-not $env:CLAUDE_AI_SESSION_KEY) { $env:CLAUDE_AI_SESSION_KEY = "" }
    if (-not $env:CLAUDE_WEB_SESSION_KEY) { $env:CLAUDE_WEB_SESSION_KEY = "" }
    if (-not $env:CLAUDE_WEB_COOKIE) { $env:CLAUDE_WEB_COOKIE = "" }

    # .env Datei fuer docker-compose erstellen
    $envContent = @"
OPENCLAW_CONFIG_DIR=$CONFIG_DIR
OPENCLAW_WORKSPACE_DIR=$WORKSPACE_DIR
OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
OPENCLAW_IMAGE=openclaw:local
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_BRIDGE_PORT=18790
OPENCLAW_GATEWAY_BIND=loopback
CLAUDE_AI_SESSION_KEY=
CLAUDE_WEB_SESSION_KEY=
CLAUDE_WEB_COOKIE=
"@
    $envContent | Out-File -FilePath "$OPENCLAW_REPO\.env" -Encoding ascii -NoNewline

    Push-Location $OPENCLAW_REPO
    # ErrorActionPreference temporaer auf Continue setzen
    # da docker compose Warnungen auf stderr ausgibt
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker compose down 2>&1 | Out-Null
    docker compose up -d openclaw-gateway 2>&1
    $ErrorActionPreference = $prevEAP
    Pop-Location
} else {
    # Fallback: Community-Image direkt starten
    Write-Host "  Nutze Community-Image ghcr.io/phioranex/openclaw-docker..." -ForegroundColor Yellow
    docker run -d `
        --name openclaw `
        --restart unless-stopped `
        -v "${CONFIG_DIR}:/home/node/.openclaw" `
        -v "${WORKSPACE_DIR}:/home/node/.openclaw/workspace" `
        -p 18789:18789 `
        -e "OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN" `
        ghcr.io/phioranex/openclaw-docker:latest `
        gateway start --foreground
}

Start-Sleep -Seconds 3

# --- Fertig ---
Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Setup abgeschlossen!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Dashboard URL:" -ForegroundColor Cyan
Write-Host "  http://127.0.0.1:18789/?token=$GATEWAY_TOKEN" -ForegroundColor White
Write-Host ""
Write-Host "Token (fuer spaeter):" -ForegroundColor Cyan
Write-Host "  $GATEWAY_TOKEN" -ForegroundColor White
Write-Host ""
Write-Host "Model: $OLLAMA_MODEL" -ForegroundColor Cyan
Write-Host "Config: $CONFIG_DIR\openclaw.json" -ForegroundColor Cyan
Write-Host ""
Write-Host "WICHTIG: Ollama muss auf 0.0.0.0 lauschen!" -ForegroundColor Yellow
Write-Host "  In neuem Terminal:" -ForegroundColor Yellow
Write-Host "    set OLLAMA_HOST=0.0.0.0:11434" -ForegroundColor White
Write-Host "    ollama serve" -ForegroundColor White
Write-Host ""
Write-Host "Logs anzeigen:" -ForegroundColor Cyan
Write-Host "  docker compose -f $OPENCLAW_REPO\docker-compose.yml logs -f openclaw-gateway" -ForegroundColor White
Write-Host "  (oder: docker logs -f openclaw)" -ForegroundColor Gray
Write-Host ""

# URL in Zwischenablage kopieren
try {
    "http://127.0.0.1:18789/?token=$GATEWAY_TOKEN" | Set-Clipboard
    Write-Host "(Dashboard-URL in Zwischenablage kopiert)" -ForegroundColor Gray
} catch {}