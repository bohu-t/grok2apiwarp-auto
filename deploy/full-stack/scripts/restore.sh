#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT=${COMPOSE_PROJECT_NAME:-grok2api-full-stack}
SOURCE=${1:-}

if [[ -z "$SOURCE" || ! -d "$SOURCE" ]]; then
  echo "usage: RESTORE_CONFIRM=YES $0 /path/to/backup" >&2
  exit 2
fi
if [[ ${RESTORE_CONFIRM:-} != YES ]]; then
  echo "refusing destructive restore; set RESTORE_CONFIRM=YES" >&2
  exit 2
fi
if [[ -f "$ROOT_DIR/.env" ]]; then
  docker compose --project-directory "$ROOT_DIR" ps --status running --quiet | grep -q . && {
    echo "refusing restore while stack containers are running" >&2
    exit 2
  }
fi
(cd "$SOURCE" && sha256sum -c SHA256SUMS)

for logical in grok2api-data quality-guard-state resin-cache resin-state resin-log register-console-runtime; do
  archive="$SOURCE/volumes/${logical}.tgz"
  [[ -f "$archive" ]] || continue
  volume="${PROJECT}_${logical}"
  docker volume create "$volume" >/dev/null
  docker run --rm -v "$volume:/target" -v "$SOURCE/volumes:/backup:ro" alpine:3.23 \
    sh -ec "find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; tar -C /target -xzf /backup/${logical}.tgz"
done

if [[ -f "$SOURCE/runtime.tgz" ]]; then
  tar -C "$ROOT_DIR" -xzf "$SOURCE/runtime.tgz"
fi
printf 'restore completed from %s; review local secrets before starting the stack\n' "$SOURCE"
