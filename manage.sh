#!/bin/bash
COMPOSE_DIR="$(dirname "$0")/openclaw"

case "$1" in
  start)
    echo "=== Starting OpenClaw ==="
    cd "$COMPOSE_DIR" && docker compose up -d 2>&1
    echo ""
    docker ps -a --filter "name=openclaw" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    ;;
  stop)
    echo "=== Stopping OpenClaw ==="
    cd "$COMPOSE_DIR" && docker compose down 2>&1
    ;;
  restart)
    echo "=== Restarting OpenClaw ==="
    cd "$COMPOSE_DIR" && docker compose down 2>&1 && docker compose up -d 2>&1
    echo ""
    docker ps -a --filter "name=openclaw" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    ;;
  status)
    echo "=== Container Status ==="
    docker ps -a --filter "name=openclaw" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "=== Gateway Logs (last 20 lines) ==="
    docker logs --tail 20 openclaw-openclaw-gateway-1 2>&1
    ;;
  *)
    echo "Usage: ./manage.sh {start|stop|restart|status}"
    exit 1
    ;;
esac
