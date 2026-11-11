# Docker 生产部署（大肥鱼鱼咖全套）

一条 Compose 启动：**对话引擎** + **fish-api** + **fish-console（含 Nginx 反代 `/api`）**。

## 前置

- 服务器已装 [Docker](https://docs.docker.com/engine/install/) 与 Compose 插件
- 域名 A 记录指向服务器（HTTPS 可在宿主机再套 Caddy/Nginx，或把 443 反代到 `FISH_HTTP_PORT`）

## 步骤

```bash
git clone <your-repo> /opt/dafeiyu
cd /opt/dafeiyu

cp deploy/.env.example deploy/.env
# 编辑 deploy/.env：FISH_PUBLIC_URL、FISH_CORS_ORIGINS、FISH_JWT_SECRET、FISH_ADMIN_EMAILS 等

docker compose --env-file deploy/.env -f compose.prod.yml up -d --build
```

| 端口 | 说明 |
| --- | --- |
| `${FISH_HTTP_PORT:-80}` | 用户中心 + `/api` |
| `127.0.0.1:6185` | 运营后台（仅本机；SSH 隧道或内网 Nginx 访问） |

## 首次必做

1. **引擎配置**：浏览器经隧道打开 `http://127.0.0.1:6185`，登录 `data/cmd_config.json` 中的运营账号，配置模型与适配器。
2. **OpenAPI Key**：在运营台创建 API Key（需 bot + config 等 scope），写入 `deploy/.env` 的 `FISH_ASTRBOT_API_KEY`，然后：
   ```bash
   docker compose --env-file deploy/.env -f compose.prod.yml up -d --force-recreate fish-api
   ```
3. **QQ 出口 IP**：把 `FISH_QQ_EGRESS_IP` 设为服务器公网 IPv4，并在 QQ 开放平台填入白名单。

## HTTPS（宿主机反代示例）

Nginx/Caddy 监听 443，反代到 `http://127.0.0.1:80`（或你设的 `FISH_HTTP_PORT`），证书用 certbot 或 Caddy 自动申请。勿把 6185 直接暴露到公网。

## 数据卷

| 卷 | 内容 |
| --- | --- |
| `astrbot_data` | 引擎 `data/`（机器人、配置、模型用量库） |
| `fish_api_data` | 客户 SQLite `fish.db` |

备份这两个卷对应的数据目录（`docker volume inspect` 查路径）。

## 常用命令

```bash
docker compose --env-file deploy/.env -f compose.prod.yml ps
docker compose --env-file deploy/.env -f compose.prod.yml logs -f fish-api
docker compose --env-file deploy/.env -f compose.prod.yml up -d --build web   # 仅改 VITE_* 后重建前台
```

## 与根目录 `compose.yml` 区别

- `compose.yml`：仅上游 AstrBot 单容器示例。
- `compose.prod.yml`：本仓魔改引擎 + fish 全套，请用本文件部署鱼咖。
