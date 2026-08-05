#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT=${COMPOSE_PROJECT_NAME:-grok2api-full-stack}
export RESIN_CACHE_DB=${RESIN_CACHE_DB:-/var/lib/docker/volumes/${PROJECT}_resin-cache/_data/cache.db}
export SINGBOX_CONFIG=${SINGBOX_CONFIG:-$ROOT_DIR/runtime/sing-box/config.json}
export BACKUP_DIR=${BACKUP_DIR:-$ROOT_DIR/runtime/backups}
export GROK_DB=${GROK_DB:-/var/lib/docker/volumes/${PROJECT}_grok2api-data/_data/backend.db}
export GROK_CONFIG=${GROK_CONFIG:-$ROOT_DIR/runtime/grok2api/config.yaml}
export GROK_API_BASE=${GROK_API_BASE:-http://127.0.0.1:${GROK2API_PORT:-28086}/api/admin/v1}
export GROK_CONTAINER=${GROK_CONTAINER:-grok2api}
export SINGBOX_CONTAINER=${SINGBOX_CONTAINER:-sing-box-bridge}
export GROK_PROXY_HOST=${GROK_PROXY_HOST:-sing-box-bridge}
export BASE_PORT=${RESIN_BRIDGE_BASE_PORT:-10801}
export MAX_NODES=${RESIN_BRIDGE_MAX_NODES:-300}
export DELETE_STALE=${RESIN_BRIDGE_DELETE_STALE:-1}

set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/runtime/quality-guard.env"
set +a
exec python3 "$ROOT_DIR/sync/resin_to_singbox_bridge.py"
