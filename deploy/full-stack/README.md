# Grok2API Full Stack — 部署教程

本目录是 Grok2API 完整栈的部署包。GitHub 保存源码和部署脚本，运行镜像由 `.env.example` 指定；目标服务器不需要现场构建。

> ⚠️ 本教程用于新服务器部署或独立测试环境。**不要在现有生产目录中直接执行 `docker compose down` 或 `up -d`**；当前生产环境不在本次发布切换范围内。

## 组件说明

| 服务 | 用途 |
|------|------|
| `grok2api` | Go 后端 + 前端，SQLite 持久化 |
| `resin` | 订阅、代理节点及健康状态管理 |
| `sing-box-bridge` | 为 Resin 中选出的节点提供稳定 SOCKS 入站 |
| `flaresolverr` | 出口流程使用的 challenge-solving 依赖 |
| `egress-quality-guard` | 节点主动/被动质量检测及隔离状态管理 |
| `console` | 浏览器注册任务控制台 |
| `sync/resin_to_singbox_bridge.py` | 宿主机 root 同步工具：生成 sing-box 路由并同步 Grok2API 出口节点 |

所有对外端口默认只绑定 `127.0.0.1`。需要远程访问时应配置带认证的 HTTPS 反向代理或安全隧道，不要直接把管理端口暴露到公网。

## 部署边界

- GitHub 保存源码、Compose、初始化和运维脚本。
- 运行镜像由 `.env.example` 指定，提前构建好，目标机无需 `docker compose build`。
- 目标机只执行 `docker compose pull`。
- `.env`、密码、Token、账号、订阅、数据库、任务和日志不进入 Git。
- **当前生产容器不在本次发布范围内，不需要切换、重启或重建。**

## 目标机要求

- Linux x86_64
- Git
- Docker Engine + Docker Compose v2
- Python 3 + PyYAML（系统包 `python3-yaml` 或 `pip install PyYAML`）
- OpenSSL

同步脚本由 root 执行，因为需要读取 Docker named volume 并调用 `docker cp`/`docker exec`。

## 获取代码

```bash
git clone https://github.com/bohu-t/grok2apiwarp-auto.git /opt/grok2apiwarp-auto
cd /opt/grok2apiwarp-auto/deploy/full-stack
```

如果仓库已存在：

```bash
cd /opt/grok2apiwarp-auto
git pull --ff-only
cd deploy/full-stack
```

## 初始化运行目录

```bash
./scripts/init.sh
```

`init.sh` 会：

- 从 `.env.example` 复制 `.env`（如果不存在）
- 从 `templates/` 复制 `quality-guard.env`、`register-console.env`、`sing-box/config.json`（如果不存在）
- 从 `vendor/grok2api/config.example.yaml` 复制 `runtime/grok2api/config.yaml` 并自动替换 JWT secret、凭据加密密钥和管理员密码（如果不存在）
- 用 `secrets.token_urlsafe(32)` 替换 `.env` 中的 `RESIN_ADMIN_TOKEN` 和 `RESIN_PROXY_TOKEN` 占位符

**初始化脚本是幂等的，不会覆盖已有文件**。记录生成的管理员密码（在 `runtime/grok2api/config.yaml` 的 `bootstrapAdmin.password` 字段），妥善保存。

## 检查本机配置

主要文件：

| 文件 | 说明 |
|------|------|
| `.env` | 镜像地址、绑定地址、端口 |
| `runtime/grok2api/config.yaml` | Grok2API 配置和管理员初始化信息 |
| `runtime/quality-guard.env` | 质量守卫配置 |
| `runtime/register-console.env` | 注册控制台默认参数 |
| `runtime/sing-box/config.json` | sing-box 配置（同步工具会替换启动引导文件） |

运行静态检查：

```bash
./scripts/validate.sh
```

`validate.sh` 会：

- 检查所有必需文件存在且非空
- 检查 `.env`、`config.yaml`、`quality-guard.env` 中没有未替换的 `replace-with-` 占位符
- 校验 `sing-box/config.json` 为合法 JSON
- 编译检查 `sync/resin_to_singbox_bridge.py`
- 语法检查所有 `.sh` 脚本
- 运行 `docker compose config --quiet`

验证 Compose 最终解析结果：

```bash
docker compose config --images
```

输出应全部指向 `.env.example` 中指定的固定镜像标签，且 Compose 中不应包含 `build:` 指令。

## 拉取镜像

```bash
docker compose pull
```

这一步只下载镜像，不会启动或重建容器。检查镜像列表：

```bash
docker compose images
```

## 启动基础服务

首次启动先运行基础服务，不立即启动质量守卫：

```bash
docker compose up -d resin sing-box-bridge flaresolverr grok2api console
```

查看状态和日志：

```bash
docker compose ps
docker compose logs --tail=100 grok2api
docker compose logs --tail=100 resin
docker compose logs --tail=100 sing-box-bridge
```

确认容器没有持续重启，等待 Grok2API 进入 healthy 状态。

## 首次业务配置

基础服务健康后，按顺序完成：

1. 使用 `runtime/grok2api/config.yaml` 中 `bootstrapAdmin.password` 登录 Grok2API。
2. 为质量守卫创建独立 client key。
3. 把 client key ID 写入 `runtime/quality-guard.env` 的 `QUALITY_GUARD_CLIENT_KEY_ID`。
4. 通过 Resin 管理界面或 API 配置订阅。
5. 等待 Resin 缓存中出现可用健康节点。
6. 按需填写 `runtime/register-console.env` 中的注册默认参数。

> 不要在文档、Issue、聊天消息或 Git 提交中粘贴真实 client key、订阅地址、管理员 Token 或账号数据。

## 首次同步出口节点

确认 Resin 已获得健康节点后，以 root 身份运行：

```bash
sudo ./scripts/sync-egress.sh
```

同步工具会：

1. 从 Resin named volume 读取缓存
2. 生成 sing-box 候选配置
3. 在现有 sing-box 容器内验证候选配置
4. 验证通过后替换 bridge 配置
5. 同步 Grok2API 出口节点

同步后检查：

```bash
docker compose ps
docker compose logs --tail=100 sing-box-bridge
docker compose logs --tail=100 grok2api
```

**不要并发运行多个同步任务。** 需要持续同步时，可在确认单次执行成功后配置 root 的 systemd timer 或 cron；推荐间隔为 15 分钟，并使用文件锁防止任务重叠。

## 启动质量守卫

完成 client key 和出口节点配置后：

```bash
docker compose up -d egress-quality-guard
```

检查：

```bash
docker compose ps egress-quality-guard
docker compose logs --tail=200 egress-quality-guard
```

如果日志提示 client key、API 地址或节点配置错误，先修正 `runtime/quality-guard.env`，再重建：

```bash
docker compose up -d --force-recreate egress-quality-guard
```

## 最终验收

```bash
./scripts/validate.sh
docker compose config --images
docker compose ps
docker compose logs --tail=100 grok2api
docker compose logs --tail=100 egress-quality-guard
```

验收要点：

- 所有容器运行或健康，没有重启循环
- 所有镜像来自阿里云固定标签
- Grok2API 可在本机绑定端口访问
- Resin 已产生健康节点
- sing-box 候选配置验证成功
- Grok2API 出口节点已同步
- 质量守卫能够调用专用 client key
- Git 工作区没有意外出现 `.env`、数据库、日志或备份归档

## 备份

```bash
./scripts/backup.sh [destination]
```

默认保存到 `/vol3/openclaw-backups/grok2api-full-stack/<timestamp>`。脚本会归档本地运行配置（`runtime/` + `.env`）和六个 named volume，并生成 SHA-256 校验文件。

备份中含有敏感数据，应：
- 通过安全通道传输
- 存放在访问受控、最好加密的位置
- 不上传 GitHub
- 不公开分享

## 迁移或恢复已有状态

先把 `backup.sh` 生成的完整备份目录安全复制到目标机。

```bash
docker compose down
RESTORE_CONFIRM=YES ./scripts/restore.sh /path/to/backup
docker compose up -d
```

恢复脚本具有两层保护：
- 栈容器仍在运行时拒绝恢复
- 未设置 `RESTORE_CONFIRM=YES` 时拒绝清空目标 volume

恢复会清空目标 volume 的现有内容。**不要在当前生产环境执行恢复**，除非已获得明确授权并完成离线备份和回滚方案。

## 更新部署代码和镜像

更新前先备份，阅读发布说明，在测试环境验证。固定标签不会自动漂移。

```bash
cd /opt/grok2apiwarp-auto/deploy/full-stack
./scripts/backup.sh

git pull --ff-only
./scripts/validate.sh
docker compose pull
docker compose config --images
```

到这里仍然没有切换运行容器。只有在你明确决定更新这个目标环境并接受容器重建时，才执行：

```bash
docker compose up -d
```

> 当前生产运行环境明确保持现状，**不要把上述最后一步用于现有生产服务器**。

## 现有生产环境：不切换说明

部署包的准备和验证不会影响现有生产容器。以下操作是安全的：

- `git clone` / `git pull`
- `./scripts/init.sh`
- `./scripts/validate.sh`
- `docker compose pull`
- `docker compose config --images`

以下操作会改变运行容器，未经授权不应在生产环境执行：

- `docker compose up -d`
- `docker compose down`
- `docker compose up -d --force-recreate`
- `./scripts/restore.sh`

## 不进入 Git 的内容

以下内容被 `.gitignore` 有意排除：

- `.env` 和所有生成的秘密
- `runtime/` 下的所有运行时文件
- Grok2API 数据库、账号、凭据、媒体和 client key
- Resin 订阅 URL、缓存、状态和日志
- 自动生成的 sing-box 节点配置
- quality-guard 状态及运行时配置
- 注册控制台任务、日志和数据库
- 备份归档

发布前检查：

```bash
git status --short --ignored
```

## 开发者验证

普通目标机只需执行：

```bash
./scripts/validate.sh
docker compose pull
docker compose config --images
```

只有开发或发布镜像时才需要从仓库根目录运行源码测试：

```bash
(cd vendor/grok2api/backend && go test ./...)
(cd vendor/grok2api/frontend && corepack pnpm install --frozen-lockfile && corepack pnpm build)
python3 -m unittest discover -s vendor/grok2api/tools/egress-quality-guard -p '*_test.py'
```

目标部署机无需运行这些源码构建步骤。

## 常见问题

### Compose 仍显示旧镜像或 GHCR

检查本机 `.env` 是否是旧版本，重新对照 `.env.example`，然后执行：

```bash
docker compose config --images
```

不要只看 Compose 源文件；环境变量可能覆盖镜像地址。

### 同步脚本无法读取 Resin 缓存

确认：
- 使用 root 执行
- `COMPOSE_PROJECT_NAME` 没有被修改（默认 `grok2api-full-stack`）
- Resin volume 已创建且 Resin 已写入缓存
- Python 3 和 PyYAML 已安装
- `sing-box-bridge` 容器正在运行

### 质量守卫启动失败

先检查 `runtime/quality-guard.env` 中的：
- `GROK2API_ADMIN_USERNAME` / `GROK2API_ADMIN_PASSWORD`
- `QUALITY_GUARD_CLIENT_KEY_ID`

再查看日志：

```bash
docker compose logs --tail=200 egress-quality-guard
```

### 端口无法从远程访问

默认绑定 `127.0.0.1` 是安全设计，不是故障。推荐配置带认证的 HTTPS 反向代理或隧道，不建议直接改成公网监听。

---

运行时镜像来自固定快照标签，目标机无需构建镜像。同步工具因需要读取 Docker volume 并调用容器验证，所以保留为宿主机 root-only 脚本，绝不能暴露成网络 API。
