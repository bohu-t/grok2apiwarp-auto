#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_DIR="$ROOT_DIR/runtime"
mkdir -p "$RUNTIME_DIR/grok2api" "$RUNTIME_DIR/sing-box" "$RUNTIME_DIR/backups"
chmod 700 "$RUNTIME_DIR" "$RUNTIME_DIR/grok2api" "$RUNTIME_DIR/sing-box" "$RUNTIME_DIR/backups"
umask 077
rand() { openssl rand -hex 32; }

created_config=0
if [[ ! -s "$ROOT_DIR/.env" ]]; then
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
fi
if [[ ! -s "$RUNTIME_DIR/quality-guard.env" ]]; then
  cp "$ROOT_DIR/templates/quality-guard.env.example" "$RUNTIME_DIR/quality-guard.env"
fi
if [[ ! -s "$RUNTIME_DIR/register-console.env" ]]; then
  cp "$ROOT_DIR/templates/register-console.env.example" "$RUNTIME_DIR/register-console.env"
fi
if [[ ! -s "$RUNTIME_DIR/sing-box/config.json" ]]; then
  cp "$ROOT_DIR/templates/sing-box.bootstrap.json" "$RUNTIME_DIR/sing-box/config.json"
fi
if [[ ! -s "$RUNTIME_DIR/grok2api/config.yaml" ]]; then
  created_config=1
  admin_password=$(rand)
  cp "$ROOT_DIR/../../vendor/grok2api/config.example.yaml" "$RUNTIME_DIR/grok2api/config.yaml"
  sed -i "s/replace-with-at-least-32-characters/$(rand)/; s#replace-with-base64-key#$(openssl rand -base64 32 | tr -d '\n')#; s/replace-with-a-strong-password/$admin_password/" "$RUNTIME_DIR/grok2api/config.yaml"
fi

python3 - "$ROOT_DIR/.env" "$RUNTIME_DIR/quality-guard.env" "$created_config" "${admin_password:-}" <<'PY'
from pathlib import Path
import secrets
import sys

def update(path, values, placeholders_only=False):
    lines=path.read_text().splitlines()
    out=[]
    seen=set()
    for line in lines:
        key=line.split('=',1)[0] if '=' in line else ''
        old=line.split('=',1)[1] if '=' in line else ''
        if key in values and (not placeholders_only or not old or old.startswith('replace-with-')):
            line=f'{key}={values[key]}'
        if key:
            seen.add(key)
        out.append(line)
    for key,value in values.items():
        if key not in seen:
            out.append(f'{key}={value}')
    path.write_text('\n'.join(out)+'\n')

update(Path(sys.argv[1]), {
    'RESIN_ADMIN_TOKEN': secrets.token_urlsafe(32),
    'RESIN_PROXY_TOKEN': secrets.token_urlsafe(32),
}, placeholders_only=True)
if sys.argv[3] == '1':
    update(Path(sys.argv[2]), {'GROK2API_ADMIN_PASSWORD': sys.argv[4]})
PY

chmod 600 "$ROOT_DIR/.env" "$RUNTIME_DIR"/*.env "$RUNTIME_DIR/grok2api/config.yaml"
printf 'initialized runtime under %s\n' "$RUNTIME_DIR"
