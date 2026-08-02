# token-sink

结果落池模块。

默认对接 [grok2api](https://github.com/chenyme/grok2api) 兼容的管理接口。注册成功后，执行器会把新增 `sso` token 推送到 `api.endpoint`。

当前约定：

- `api.endpoint`：token 管理接口。支持：
  - 轻量账号池中转服务：`http://192.168.124.168:2202/api/accounts/buffer`
  - grok2api v3：`http://127.0.0.1:8000/api/admin/v1/accounts/import`
  - grok2api v2：`http://127.0.0.1:8000/admin/api/tokens/add`
- `api.token`：管理员密码/管理口令；推送时会作为 `Authorization: Bearer <api.token>` 发送。
- `api.append=true`：先读取存量再去重合并，保护已有 token（仅 v2/自定义 JSON 接口支持）。
- `api.append=false`：直接以本次结果覆盖远端数据（仅 v2/自定义 JSON 接口支持）。
- `api.import_type`：grok2api v3 专属，指定账号类型：`build`/`console`/`web`。

建议后续继续在这里收敛的功能：

- token 入池结果校验
- 可选回写运行统计
- 死信重试
- 多个 sink 目标并发推送

在当前一体化部署里，根目录 [docker-compose.yml](../../docker-compose.yml) 已经内置 `grok2api` 服务。控制台默认会把 `api.endpoint` 指向轻量账号池中转服务；如果你想直接入 grok2api，也可以改为：

- `http://grok2api:8000/api/admin/v1/accounts/import`（v3）
- `http://grok2api:8000/admin/api/tokens/add`（v2 旧版）

## 独立轻量账号池中转服务

如果注册机一次性导入大量账号，不要直接打主 `chatgpt2api`。主平台会被大量写入、补池和测活拖慢甚至卡死；也不需要完整再起一个 `chatgpt2api`，只需要一个轻量账号池服务。

推荐链路：

1. 注册机推送到轻量账号池服务：`POST /api/accounts/buffer`
2. 账号池只负责 SQLite 落盘存 token，不承接生产请求、不启动测活线程
3. 主 `chatgpt2api` 再按批次从账号池 `POST /api/accounts/pop` 取账号，导入自己的中转仓库/主池

当前本机约定的中转池入口示例：

- `http://192.168.124.168:2202/api/accounts/buffer`

请求体：

```json
{
  "tokens": ["access_token_1", "access_token_2"],
  "source": "grok-register"
}
```

鉴权仍使用 `Authorization: Bearer <管理密钥>`。
