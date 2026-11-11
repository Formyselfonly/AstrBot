# Docker 生产部署（大肥鱼鱼咖全套）

一条 Compose 启动：**对话引擎** + **fish-api** + **fish-console（含 Nginx 反代 `/api`）**。

**推荐流程：先在开发机用同一套 `compose.prod.yml` 构建并验收，再原样上服务器。** 避免在远端 tmux 里排 Dockerfile / pnpm / hatchling 等问题。

## 本地先于服务器（Mac / Linux）

前置：安装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)（Mac）或 Docker Engine + Compose 插件。

```bash
cd /path/to/AstrBot
cp deploy/.env.local.example deploy/.env
# 可选：改 FISH_JWT_SECRET、FISH_ADMIN_EMAILS

chmod +x scripts/docker-prod-up.sh
./scripts/docker-prod-up.sh
```

| 地址 | 说明 |
| --- | --- |
| http://127.0.0.1:8080 | 客户站 + 同域 `/api`（`FISH_HTTP_PORT=8080`，避免占 80） |
| http://127.0.0.1:6185 | 运营后台 WebUI |

验收示例：

```bash
./scripts/docker-prod-up.sh ps
curl -fsSI http://127.0.0.1:8080/ | head -n1
# fish-api health is not under /api; check inside the container or via exec:
docker exec dafeiyu-fish-api curl -fsS http://127.0.0.1:8800/health
```

首次 `up --build` 会较久（**astrbot** 镜像最大）。失败时在本机直接 `docker compose … logs` / 改 Dockerfile 再构建，比 SSH 省事。

停掉本地栈：

```bash
./scripts/docker-prod-up.sh down
```

本地与生产共用 `compose.prod.yml`；生产把 `deploy/.env` 换成域名、HTTPS、`FISH_HTTP_PORT=80` 等即可（可复制 `deploy/.env.example` 再改）。

## 前置（服务器）

- 服务器已装 [Docker](https://docs.docker.com/engine/install/) 与 Compose 插件
- **根域还有别的服务时**：不要把 Compose 直接绑在 `0.0.0.0:80`（会抢走所有域名的 80 流量）。默认 `FISH_BIND_ADDRESS=127.0.0.1`、`FISH_HTTP_PORT=8080`，由宿主机 **Caddy/Nginx 按子域分流**。
- Cloudflare：仅 **`fish` 子域** A 记录指向本机（或与反代一致）；**`@` 根域** 指向 Pages / 另一台机 / 另一反代 upstream，不要和鱼咖抢同一裸 `:80` Docker 映射。

### 子域 + 根域共存（示例）

| DNS | 指向 |
| --- | --- |
| `fish.kerryzhengai.com` | 本机公网 IP（橙云可开） |
| `kerryzhengai.com` (`@`) | 其他服务（Pages、另一 IP 等） |

宿主机 Caddy（443）示意：

```text
fish.kerryzhengai.com  → reverse_proxy 127.0.0.1:8080
kerryzhengai.com       → 你的主站 upstream
```

`deploy/.env` 中 `FISH_SITE_HOST=fish.kerryzhengai.com`；Nginx 容器会 **拒绝** 用根域 Host 访问鱼咖（避免误配时根域打开登录页）。

## 步骤（服务器）

```bash
git clone <your-repo> /opt/dafeiyu
cd /opt/dafeiyu

cp deploy/.env.example deploy/.env
# 编辑 deploy/.env：FISH_PUBLIC_URL、FISH_CORS_ORIGINS、FISH_JWT_SECRET、FISH_ADMIN_EMAILS 等

docker compose --env-file deploy/.env -f compose.prod.yml up -d --build
```

| 端口 | 说明 |
| --- | --- |
| `${FISH_BIND_ADDRESS}:${FISH_HTTP_PORT}`（默认 `127.0.0.1:8080`） | 用户中心 + `/api`（经宿主机反代对外） |
| `127.0.0.1:6185` | 运营后台（仅本机；SSH 隧道或内网 Nginx 访问） |

## 首次必做

1. **引擎配置**：浏览器经隧道打开 `http://127.0.0.1:6185`，登录 `data/cmd_config.json` 中的运营账号，配置模型与适配器。
2. **OpenAPI Key**：在运营台创建 API Key（需 bot + config 等 scope），写入 `deploy/.env` 的 `FISH_ASTRBOT_API_KEY`，然后：
   ```bash
   docker compose --env-file deploy/.env -f compose.prod.yml up -d --force-recreate fish-api
   ```
3. **QQ 出口 IP**：把 `FISH_QQ_EGRESS_IP` 设为服务器公网 IPv4，并在 QQ 开放平台填入白名单。

## HTTPS（宿主机反代示例）

Caddy/Nginx 监听 443，**仅 `fish` 子域** 反代到 `http://127.0.0.1:${FISH_HTTP_PORT}`。勿把 6185 直接暴露到公网。

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
