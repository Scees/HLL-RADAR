#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Ensure config exists
if [ ! -f config.toml ]; then
    echo "Error: config.toml not found. Copy config.example.toml and edit it first:"
    echo "  cp config.example.toml config.toml"
    exit 1
fi

# Create logs directory
mkdir -p logs

# Read a simple value from a TOML section/key pair.
toml_get() {
    local section="$1"
    local key="$2"
    local file="$3"
    awk -v section="$section" -v key="$key" '
    BEGIN { in_section = 0 }
    /^[[:space:]]*\[/ {
      in_section = ($0 ~ "^[[:space:]]*\\[" section "\\][[:space:]]*$")
    }
    in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value = $0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      sub(/[[:space:]]*#.*/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }' "$file"
}

# Allow config.toml to provide deployment overrides.
if [ -z "${HLL_RADAR_HOST_PORT:-}" ]; then
    HLL_RADAR_HOST_PORT="$(toml_get "deployment" "host_port" "config.toml" || true)"
    export HLL_RADAR_HOST_PORT
fi

if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    CLOUDFLARE_TUNNEL_TOKEN="$(toml_get "deployment" "cloudflare_tunnel_token" "config.toml" || true)"
    export CLOUDFLARE_TUNNEL_TOKEN
fi

APP_PORT="${HLL_RADAR_HOST_PORT:-8080}"

COMPOSE_ARGS=()
if [ "${1:-}" = "tunnel" ] || [ "${1:-}" = "--tunnel" ]; then
    if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
        echo "Error: deployment.cloudflare_tunnel_token is empty in config.toml."
        echo "Set it in [deployment], or export CLOUDFLARE_TUNNEL_TOKEN before starting with tunnel."
        exit 1
    fi
    COMPOSE_ARGS+=(--profile tunnel)
fi

echo "Building and starting HLL-RADAR..."
docker compose "${COMPOSE_ARGS[@]}" build --no-cache hll-radar
docker compose "${COMPOSE_ARGS[@]}" up -d

echo ""
echo "Waiting for services to be healthy..."
docker compose "${COMPOSE_ARGS[@]}" ps

echo ""
echo "HLL-RADAR is running:"
echo "  App:    http://localhost:${APP_PORT}"
echo "  Health: http://localhost:${APP_PORT}/health"
echo "  Logs:   ./logs/"
echo ""
echo "Follow logs:  docker compose ${COMPOSE_ARGS[*]} logs -f"
echo "With tunnel:  ./scripts/start.sh tunnel"
echo "Stop:         ./scripts/stop.sh"
