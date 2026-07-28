#!/usr/bin/env sh
set -eu

# ⚠️ DEPRECATED: grok2api v3 自带 entrypoint（docker/entrypoint.sh）
# 本脚本仅用于向后兼容旧部署配置，新版请使用 Dockerfile 内置 entrypoint。

CONFIG_SOURCE="${GROK2API_CONFIG_SOURCE:-/run/grok2api/config.yaml}"
DATA_DIR="${DATA_DIR:-/app/data}"

echo "[grok2apiwarp] 检测到旧版 entrypoint，自动适配 v3 配置格式..."

mkdir -p "$DATA_DIR"

if [ ! -f /app/config.yaml ]; then
  if [ -f "$CONFIG_SOURCE" ]; then
    cp "$CONFIG_SOURCE" /app/config.yaml
    echo "[grok2apiwarp] 已复制配置文件: $CONFIG_SOURCE -> /app/config.yaml"
  else
    echo "[grok2apiwarp] ⚠️ 配置文件不存在: $CONFIG_SOURCE" >&2
    echo "[grok2apiwarp] 请将 config.yaml 挂载到 /run/grok2api/config.yaml" >&2
    exit 1
  fi
fi

exec /app/grok2api --config /app/config.yaml --listen "0.0.0.0:8000"
