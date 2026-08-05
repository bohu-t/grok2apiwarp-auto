#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT=${COMPOSE_PROJECT_NAME:-grok2api-full-stack}
DEST=${1:-/vol3/openclaw-backups/grok2api-full-stack/$(date +%Y%m%d-%H%M%S)}
umask 077
mkdir -p "$DEST/volumes"
chmod 700 "$DEST"

if [[ -d "$ROOT_DIR/runtime" ]]; then
  tar -C "$ROOT_DIR" -czf "$DEST/runtime.tgz" runtime .env
fi
cp "$ROOT_DIR/docker-compose.yml" "$DEST/docker-compose.yml"

for logical in grok2api-data quality-guard-state resin-cache resin-state resin-log register-console-runtime; do
  volume="${PROJECT}_${logical}"
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    docker run --rm -v "$volume:/source:ro" -v "$DEST/volumes:/backup" alpine:3.23 \
      tar -C /source -czf "/backup/${logical}.tgz" .
  else
    printf 'warning: volume not found: %s\n' "$volume" >&2
  fi
done

(
  cd "$DEST"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)
printf 'backup written to %s\n' "$DEST"
