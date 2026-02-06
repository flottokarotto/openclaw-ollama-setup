# OpenClaw + Ollama Setup

One-script setup to run [OpenClaw](https://github.com/openclaw/openclaw) with a local [Ollama](https://ollama.com) model on Windows. No cloud API keys needed -- everything runs on your machine.

## What it does

The `setup.ps1` script automates the entire setup process:

1. Detects Ollama installation (even if not in PATH)
2. Verifies Docker Desktop and Ollama are running
3. Pulls the configured model if not already downloaded
4. Creates the OpenClaw config directory and `openclaw.json`
5. Builds the OpenClaw Docker image from source
6. Starts the gateway container via Docker Compose
7. Prints the dashboard URL with auth token

## Prerequisites

| Requirement | Notes |
|---|---|
| **Windows 10/11** | PowerShell 5.1+ |
| **Docker Desktop** | Must be running before setup |
| **Ollama** | [Download](https://ollama.com/download) and start with `ollama serve` |
| **OpenClaw repo** | Cloned to `~/workspace/openclaw/openclaw` (see below) |

## Quick Start

```powershell
# 1. Clone this repo
git clone https://github.com/flottokarotto/openclaw-ollama-setup.git ~/workspace/openclaw
cd ~/workspace/openclaw

# 2. Clone the OpenClaw repo
git clone https://github.com/openclaw/openclaw.git openclaw

# 3. Make sure Docker Desktop and Ollama are running
#    (start Ollama with 0.0.0.0 binding for Docker access)
$env:OLLAMA_HOST = "0.0.0.0:11434"
ollama serve

# 4. Run setup (in a new terminal)
.\setup.ps1
```

After setup completes, open the dashboard URL printed in the terminal. On first connect, approve the device pairing:

```powershell
docker exec openclaw-openclaw-gateway-1 node dist/index.js devices list
docker exec openclaw-openclaw-gateway-1 node dist/index.js devices approve <requestId>
```

## Configuration

Edit the variables at the top of `setup.ps1`:

| Variable | Default | Description |
|---|---|---|
| `$OLLAMA_MODEL` | `qwen3:14b` | Ollama model to use |
| `$OPENCLAW_REPO` | `~/workspace/openclaw/openclaw` | Path to the OpenClaw repo |
| `$CONFIG_DIR` | `~/.openclaw` | OpenClaw config directory |

### Changing the model

```powershell
# Pull a different model first
ollama pull llama3.1:8b

# Then edit $OLLAMA_MODEL in setup.ps1 and re-run
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

## Architecture

```
                    +------------------+
                    |    Browser       |
                    |  (Dashboard UI)  |
                    +--------+---------+
                             |
                             | WebSocket :18789
                             |
                    +--------+---------+
                    |   OpenClaw       |
                    |   Gateway        |
                    |   (Docker)       |
                    +--------+---------+
                             |
                             | OpenAI-compat API
                             | host.docker.internal:11434
                             |
                    +--------+---------+
                    |    Ollama        |
                    |    (Host)        |
                    |  qwen3:14b       |
                    +------------------+
```

## Troubleshooting

### Ollama not found

The script auto-detects Ollama in common locations:
- `%LOCALAPPDATA%\Programs\Ollama\ollama.exe`
- `%ProgramFiles%\Ollama\ollama.exe`

If installed elsewhere, add it to your PATH or edit the `$candidates` array in the script.

### Docker can't reach Ollama

Ollama must listen on `0.0.0.0` (not just `127.0.0.1`) for Docker to connect via `host.docker.internal`:

```powershell
$env:OLLAMA_HOST = "0.0.0.0:11434"
ollama serve
```

### Gateway config invalid

OpenClaw's `gateway.bind` only accepts: `loopback`, `lan`, `tailnet`, `auto`, `custom` -- not raw IPs.

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

## License

[MIT](LICENSE)
