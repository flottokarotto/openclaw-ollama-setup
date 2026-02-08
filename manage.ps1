param(
    [Parameter(Position=0)]
    [ValidateSet("start", "stop", "restart", "status")]
    [string]$Action
)

$ComposeDir = Join-Path $PSScriptRoot "openclaw"

function Show-Status {
    docker ps -a --filter "name=openclaw" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

switch ($Action) {
    "start" {
        Write-Host "=== Starting OpenClaw ===" -ForegroundColor Cyan
        $ErrorActionPreference = "Continue"
        docker compose -f "$ComposeDir\docker-compose.yml" up -d 2>&1
        Write-Host ""
        Show-Status
    }
    "stop" {
        Write-Host "=== Stopping OpenClaw ===" -ForegroundColor Cyan
        $ErrorActionPreference = "Continue"
        docker compose -f "$ComposeDir\docker-compose.yml" down 2>&1
    }
    "restart" {
        Write-Host "=== Restarting OpenClaw ===" -ForegroundColor Cyan
        $ErrorActionPreference = "Continue"
        docker compose -f "$ComposeDir\docker-compose.yml" down 2>&1
        docker compose -f "$ComposeDir\docker-compose.yml" up -d 2>&1
        Write-Host ""
        Show-Status
    }
    "status" {
        Write-Host "=== Container Status ===" -ForegroundColor Cyan
        Show-Status
        Write-Host ""
        Write-Host "=== Gateway Logs (last 20 lines) ===" -ForegroundColor Cyan
        docker logs --tail 20 openclaw-openclaw-gateway-1 2>&1
    }
    default {
        Write-Host "Usage: .\manage.ps1 {start|stop|restart|status}"
        exit 1
    }
}
