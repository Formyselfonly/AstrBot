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

## 对外访问：VPS 的 443 已被 3x-ui / Xray 占用

鱼咖 Docker 默认只监听 `127.0.0.1:${FISH_HTTP_PORT}`，**不要**和 Xray 抢 443。推荐 **Cloudflare Tunnel（cloudflared）**：由隧道出站连 Cloudflare，把 `fish.你的域名` 指到本机 `http://127.0.0.1:8080`，**3x-ui 配置不用改**。

### Cloudflare Tunnel 步骤（fish.kerryzhengai.com 示例）

在 VPS 上执行（需已 `docker compose` 跑通且 `curl -H "Host: fish..." http://127.0.0.1:8080/` 为 200）：

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

cloudflared tunnel login
# 浏览器选 kerryzhengai.com 域名授权

cloudflared tunnel create dafeiyu-fish
# 记下输出的 Tunnel UUID
```

创建 `/etc/cloudflared/config.yml`（把 `TUNNEL_UUID` 换成上一步 UUID）：

```yaml
tunnel: TUNNEL_UUID
credentials-file: /root/.cloudflared/TUNNEL_UUID.json

ingress:
  - hostname: fish.kerryzhengai.com
    service: http://127.0.0.1:8080
  - service: http_status:404
```

```bash
cloudflared tunnel route dns dafeiyu-fish fish.kerryzhengai.com
cloudflared service install
systemctl enable --now cloudflared
systemctl status cloudflared
```

**DNS：** `tunnel route dns` 会在 Cloudflare 创建/更新 `fish` 的 CNAME。请**删掉**旧的 `fish` → VPS IP 的 **A 记录**，避免和 Tunnel 冲突（根域 `@` 和其它子域不动）。

**fish `deploy/.env`：**

```env
FISH_PUBLIC_URL=https://fish.kerryzhengai.com
FISH_SITE_HOST=fish.kerryzhengai.com
FISH_CORS_ORIGINS=https://fish.kerryzhengai.com
```

Cloudflare 控制台 **SSL/TLS** 用默认即可（Tunnel 自带 HTTPS）。QQ 白名单仍填 **VPS 公网 IP**（机器人出站不走 Tunnel）。

### 运营控制台外网访问（HTTP 基本认证 + Tunnel）

在 **同一 Tunnel** 里加一条 ingress（示例子域 `ops`），指向本机 **6186**（`console-proxy` 容器，不是裸 6185）：

```yaml
ingress:
  - hostname: fish.kerryzhengai.com
    service: "http://127.0.0.1:8080"
  - hostname: ops.kerryzhengai.com
    service: "http://127.0.0.1:6186"
  - service: http_status:404
```

```bash
cloudflared tunnel route dns dafeiyu-fish ops.kerryzhengai.com
```

**服务器 `deploy/.env`**（仅你这台机器改，勿提交 Git）：

```env
CONSOLE_PROXY_USER=kerryzheng
CONSOLE_PROXY_PASSWORD=你的门禁密码
CONSOLE_PROXY_PORT=6186
```

```bash
docker compose --env-file deploy/.env -f compose.prod.yml --profile console-proxy up -d --build
systemctl restart cloudflared
```

浏览器打开 `https://ops.kerryzhengai.com` → 先弹 **HTTP 基本认证**（用户 `kerryzheng` + 上面密码）→ 再进 AstrBot **运营台自己的登录**（`data/cmd_config.json` 账号）。  
不要用弱密码长期暴露；基本认证不能代替运营台强密码。

`console-proxy` 的 Basic Auth **只拦 `GET /`（SPA 壳）**；`/assets/`、`/api/`、WebSocket（`/live-chat/` 等）不再做 Basic Auth，否则 WebUI 的 `crossorigin` 脚本、WebSocket、SSE 不带 `Authorization`，会出现 **白屏** 或 **Sign in 无限弹窗**。改 `nginx.conf.template` 后需 `--build` 重建 `console-proxy`。暴力破解仍主要靠 **运营台强密码**；若要更强外网门禁请用 **Cloudflare Access**。

### 备选：宿主机 Caddy 反代（仅当 443 未被 Xray 占用时）

Caddy/Nginx 监听 443，**仅 `fish` 子域** 反代到 `http://127.0.0.1:${FISH_HTTP_PORT}`。勿把 6185 直接暴露到公网。

## 数据卷

| 卷 | 内容 |
| --- | --- |
| `astrbot_data` | 引擎 `data/`（机器人、配置、模型用量库） |
| `fish_api_data` | 客户 SQLite `fish.db` |

备份这两个卷对应的数据目录（`docker volume inspect` 查路径）。

### 宿主机 Ollama（Embedding）

`compose.prod.yml` 为 `astrbot` 配置了 `host.docker.internal:host-gateway`。在运营台把 Ollama Embedding 的 API 地址设为 **`http://host.docker.internal:11434`**，不要用 `localhost`（容器内的 localhost 不是 VPS）。

Ollama 默认只监听 `127.0.0.1` 时，从容器仍可能连不上。在宿主机为 Ollama 开放对 Docker 网桥的访问，例如 systemd 覆盖里设置 `OLLAMA_HOST=0.0.0.0:11434`，重启 Ollama 后验证：

```bash
docker exec dafeiyu-astrbot curl -sS http://host.docker.internal:11434/api/tags | head
```

## 常用命令

```bash
docker compose --env-file deploy/.env -f compose.prod.yml ps
docker compose --env-file deploy/.env -f compose.prod.yml logs -f fish-api
docker compose --env-file deploy/.env -f compose.prod.yml up -d --build web   # 仅改 VITE_* 后重建前台
```

## 与根目录 `compose.yml` 区别

- `compose.yml`：仅上游 AstrBot 单容器示例。
- `compose.prod.yml`：本仓魔改引擎 + fish 全套，请用本文件部署鱼咖。
