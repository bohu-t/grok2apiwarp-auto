# Grok2API Full Stack

This deployment packages the stateless code and topology of the production stack without committing live accounts, subscriptions, databases, tokens, or proxy credentials.

## Services

- `grok2api`: vendored Go backend and frontend, SQLite persistence.
- `resin`: subscription/node inventory and health state.
- `sing-box-bridge`: one stable SOCKS inbound per selected Resin node.
- `flaresolverr`: challenge-solving dependency used by egress flows.
- `egress-quality-guard`: active/passive node quality checks and quarantine state.
- `console`: browser-based registration task console.
- `sync/resin_to_singbox_bridge.py`: root-only host tool that regenerates sing-box routes and reconciles Grok2API egress nodes.

All published ports bind to `127.0.0.1` by default. Put an authenticated reverse proxy or tunnel in front if remote access is required.

## Fresh deployment

```bash
cd deploy/full-stack
./scripts/init.sh
./scripts/validate.sh
docker compose pull
docker compose up -d resin sing-box-bridge flaresolverr grok2api console
```

After Grok2API is healthy:

1. Sign in with the bootstrap administrator password stored in `runtime/grok2api/config.yaml`.
2. Create a dedicated client key for the quality guard and set `QUALITY_GUARD_CLIENT_KEY_ID` in `runtime/quality-guard.env`.
3. Configure Resin subscriptions through its administrator interface/API and wait for `resin-cache` to contain healthy nodes.
4. Install host packages `python3`, `docker`, and Python YAML support (`python3-yaml` or `pip install PyYAML`), then run `./scripts/sync-egress.sh` once as root. It validates the generated candidate inside the existing sing-box container before replacing the bridge config, then reconciles Grok2API egress nodes.
5. Start the guard: `docker compose up -d egress-quality-guard`.
6. Fill registration defaults in `runtime/register-console.env` as needed.

For continuous Resin synchronization, install a host timer/cron that invokes `scripts/sync-egress.sh`. Do not run overlapping sync jobs. A 15-minute interval matches the inventoried production setup.

## Migrate existing state

On the source deployment, use `scripts/backup.sh [destination]`. It archives local runtime configuration plus the six named volumes and writes SHA-256 checksums. Copy the resulting directory through a secure channel.

On the target host:

```bash
docker compose down
RESTORE_CONFIRM=YES ./scripts/restore.sh /path/to/backup
docker compose up -d
```

The restore script refuses to run while stack containers are running and requires explicit confirmation because it clears target volume contents before extraction.

## What is intentionally not in Git

- `.env` and all generated secrets
- Grok2API database, accounts, credentials, media, and client keys
- Resin subscription URLs, cache, state, and logs
- generated sing-box node configuration
- quality-guard state/runtime config
- registration console tasks, logs, and database
- backup archives

These paths are ignored by `.gitignore`; run `git status --ignored` and a secret scan before every release.

## Validation

Static deployment validation:

```bash
./scripts/validate.sh
```

Source gates from the repository root:

```bash
(cd vendor/grok2api/backend && go test ./...)
(cd vendor/grok2api/frontend && corepack pnpm install --frozen-lockfile && corepack pnpm build)
python3 -m unittest discover -s vendor/grok2api/tools/egress-quality-guard -p '*_test.py'
docker compose -f deploy/full-stack/docker-compose.yml pull
```

The sync tool runs as a root-only host script because it reads Docker named-volume state and invokes `docker cp`/`docker exec` for sing-box validation. Keep it root-owned and never expose it as a network API. Runtime images are pulled from the fixed Aliyun `20260805-live` snapshot; no target-host image build is required.
