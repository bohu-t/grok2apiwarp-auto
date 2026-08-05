#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { printf "${GREEN}[deploy]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[deploy]${NC} %s\n" "$*"; }
err()  { printf "${RED}[deploy]${NC} %s\n" "$*" >&2; }

# ── safety gate ──────────────────────────────────────────────
if [[ ${DEPLOY_CONFIRM:-} != YES ]]; then
  cat >&2 <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║  一键部署将执行 docker compose up -d，会创建或重启容器。    ║
║  如果这是现有生产环境，请先阅读 README.md 中的注意事项。    ║
║                                                            ║
║  确认部署：  DEPLOY_CONFIRM=YES ./deploy.sh                 ║
╚══════════════════════════════════════════════════════════════╝
EOF
  exit 2
fi

# ── prerequisites ────────────────────────────────────────────
for cmd in docker git python3 openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "missing required command: $cmd"
    exit 1
  fi
done

if ! docker compose version >/dev/null 2>&1; then
  err "docker compose (v2) is required"
  exit 1
fi

python3 -c 'import yaml' 2>/dev/null || {
  warn "python3-yaml not found; sync-egress.sh will need it later"
}

# ── init ─────────────────────────────────────────────────────
log "initializing runtime files..."
./scripts/init.sh

# ── validate ─────────────────────────────────────────────────
log "validating deployment..."
./scripts/validate.sh

# ── pull ─────────────────────────────────────────────────────
log "pulling images..."
docker compose pull

# ── start ────────────────────────────────────────────────────
log "starting all services..."
docker compose up -d

# ── status ───────────────────────────────────────────────────
echo ""
log "deployment complete. service status:"
docker compose ps

echo ""
log "access points:"
printf "  console:    http://<host>:%s\n" "${REGISTER_CONSOLE_PORT:-18600}"
printf "  grok2api:   http://<host>:%s\n" "${GROK2API_PORT:-28086}"
printf "  resin:      http://<host>:%s\n" "${RESIN_PORT:-2260}"

echo ""
warn "next steps:"
echo "  1. log in to grok2api with the bootstrap password in runtime/grok2api/config.yaml"
echo "  2. create a client key for the quality guard → update runtime/quality-guard.env"
echo "  3. configure resin subscriptions and wait for healthy nodes"
echo "  4. run: sudo ./scripts/sync-egress.sh"
echo "  5. fill registration defaults in runtime/register-console.env"
echo "  6. set up a cron/timer for sync-egress.sh (recommended: every 15 min)"