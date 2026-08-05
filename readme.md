# Grok2API Full Stack

Grok 账号注册 + Grok2API 代理 + 出口管理的一体化部署项目。

## 组件

| 服务 | 用途 |
|------|------|
| `grok2api` | Go 后端 + 前端，SQLite 持久化，OpenAI 兼容 API |
| `resin` | 订阅、代理节点及健康状态管理 |
| `sing-box-bridge` | 为 Resin 中选出的节点提供稳定 SOCKS 入站 |
| `flaresolverr` | 出口流程使用的 challenge-solving 依赖 |
| `egress-quality-guard` | 节点主动/被动质量检测及隔离状态管理 |
| `console` | 浏览器注册任务控制台 |

## 一键部署

```bash
git clone https://github.com/bohu-t/grok2apiwarp-auto.git
cd grok2apiwarp-auto/deploy/full-stack
./deploy.sh
```

部署脚本会自动完成初始化、检查、拉取镜像和启动全部服务。首次启动后，打开控制台补充临时邮箱等参数即可开始注册。

## 手动部署

```bash
cd deploy/full-stack
./scripts/init.sh
./scripts/validate.sh
docker compose pull
docker compose up -d
```

## 启动后

- 控制台：`http://<服务器IP>:18600`
- Grok2API 管理端：`http://<服务器IP>:28086`
- 首次登录 Grok2API 使用 `runtime/grok2api/config.yaml` 中自动生成的管理员密码

## 文档

- [完整部署教程](deploy/full-stack/README.md) — 初始化、配置、同步、备份、恢复、排障
- [docs/](docs/) — 业务链路、配置字段、架构说明

## 项目结构

- [apps/](apps/) — 控制台、网络出口、注册执行器、token sink、运行时环境
- [deploy/full-stack/](deploy/full-stack/) — Compose、初始化脚本、同步工具、备份恢复
- [vendor/grok2api/](vendor/grok2api/) — Grok2API v3 后端 + 前端

## 致谢

- [ReinerBRO](https://github.com/ReinerBRO) 对仓库整理、部署验证和整合方向的推动
- [XeanYu](https://github.com/XeanYu) 和 [chenyme](https://github.com/chenyme) 的开源项目与思路
- [DrissionPage](https://github.com/g1879/DrissionPage)
- [grok2api](https://github.com/chenyme/grok2api)