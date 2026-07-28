#!/bin/sh
# grok2apiwarp-auto 配置初始化脚本
# 自动生成密钥并写入 runtime/grok2api/config.yaml

set -eu

CONFIG_FILE="${1:-runtime/grok2api/config.yaml}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$PROJECT_DIR/$CONFIG_FILE"

if [ ! -f "$CONFIG_PATH" ]; then
  echo "❌ 配置文件不存在: $CONFIG_PATH"
  echo "   请先确保 runtime/grok2api/config.yaml 模板存在"
  exit 1
fi

echo "🔐 生成密钥..."

JWT_SECRET=$(openssl rand -hex 32)
CRED_KEY=$(openssl rand -base64 32)

# 读取用户输入的 admin 密码（可选）
if [ -t 0 ]; then
  printf "📝 输入管理员密码 (留空保持默认): "
  read -r ADMIN_PASSWORD
  if [ -n "$ADMIN_PASSWORD" ]; then
    # 使用 sed 或 perl 替换
    if command -v perl >/dev/null 2>&1; then
      perl -i -pe "s/REPLACE_ME_jwtSecret_change_me_min_32_chars!!/$JWT_SECRET/" "$CONFIG_PATH"
      perl -i -pe "s/REPLACE_ME_base64_encryption_key_32_bytes==/$CRED_KEY/" "$CONFIG_PATH"
      perl -i -pe "s/change-this-admin-password/$ADMIN_PASSWORD/" "$CONFIG_PATH"
    else
      sed -i "s/REPLACE_ME_jwtSecret_change_me_min_32_chars!!/$JWT_SECRET/" "$CONFIG_PATH"
      sed -i "s/REPLACE_ME_base64_encryption_key_32_bytes==/$CRED_KEY/" "$CONFIG_PATH"
      sed -i "s/change-this-admin-password/$ADMIN_PASSWORD/" "$CONFIG_PATH"
    fi
    echo "✅ 配置已更新: $CONFIG_PATH"
    echo "   jwtSecret: $JWT_SECRET"
    echo "   credentialEncryptionKey: $CRED_KEY"
    echo "   admin密码: $ADMIN_PASSWORD"
  else
    echo "⚠️  使用默认密码，请尽快在管理端修改！"
  fi
else
  if command -v perl >/dev/null 2>&1; then
    perl -i -pe "s/REPLACE_ME_jwtSecret_change_me_min_32_chars!!/$JWT_SECRET/" "$CONFIG_PATH"
    perl -i -pe "s/REPLACE_ME_base64_encryption_key_32_bytes==/$CRED_KEY/" "$CONFIG_PATH"
  else
    sed -i "s/REPLACE_ME_jwtSecret_change_me_min_32_chars!!/$JWT_SECRET/" "$CONFIG_PATH"
    sed -i "s/REPLACE_ME_base64_encryption_key_32_bytes==/$CRED_KEY/" "$CONFIG_PATH"
  fi
  echo "✅ 密钥已生成 (非交互模式，admin 密码使用默认值)"
  echo "   jwtSecret: $JWT_SECRET"
  echo "   credentialEncryptionKey: $CRED_KEY"
fi
