#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

required=(.env runtime/grok2api/config.yaml runtime/quality-guard.env runtime/register-console.env runtime/sing-box/config.json)
for path in "${required[@]}"; do
  [[ -s "$path" ]] || { echo "missing required runtime file: $path" >&2; exit 1; }
done

for path in .env runtime/grok2api/config.yaml runtime/quality-guard.env; do
  if grep -nE 'replace-with-' "$path" | grep -v 'QUALITY_GUARD_CLIENT_KEY_ID='; then
    echo "unreplaced deployment placeholders found in $path" >&2
    exit 1
  fi
done

if grep -qE '^QUALITY_GUARD_CLIENT_KEY_ID=(|replace-with-)' runtime/quality-guard.env; then
  echo 'warning: quality guard client key is not bound; create a dedicated Grok2API client key and update runtime/quality-guard.env' >&2
fi

python3 -m json.tool runtime/sing-box/config.json >/dev/null
python3 -m py_compile sync/resin_to_singbox_bridge.py
for script in scripts/*.sh; do bash -n "$script"; done

docker compose config --quiet
printf 'full-stack static validation passed\n'
