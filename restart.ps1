# Quick restart of OpenClaw gateway (no rebuild)
$OPENCLAW_REPO = "$env:USERPROFILE\workspace\openclaw\openclaw"

$ErrorActionPreference = "Continue"
docker compose -f "$OPENCLAW_REPO\docker-compose.yml" restart openclaw-gateway 2>&1
$ErrorActionPreference = "Stop"

Write-Host "Gateway restarted." -ForegroundColor Green
Write-Host ""
Write-Host "View logs:" -ForegroundColor Cyan
Write-Host "  docker compose -f $OPENCLAW_REPO\docker-compose.yml logs -f openclaw-gateway" -ForegroundColor White
