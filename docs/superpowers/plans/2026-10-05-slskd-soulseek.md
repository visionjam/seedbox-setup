# slskd（Soulseek）接入实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 slskd（Soulseek 无头客户端）并入 seedbox-setup 栈：WebUI 8090 / Soulseek 监听口 50300，下载落 `downloads/soulseek/` 并自动进入 8899 拉回管道，凭据独立且不入库。

**Architecture:** 在现有 `docker-compose.yml` 新增 `slskd` 服务（官方镜像固定版本、`user: "1000:1000"`、`env_file: ./slskd.env`）；`bootstrap.sh` 幂等生成凭据与环境；备份脚本扩展覆盖 `slskd-config`；拉回复用现有 nginx `files` 容器（零改动）。

**Tech Stack:** Docker Compose / slskd 0.26.0 / bash / nginx（既有）。

**设计依据：** `docs/superpowers/specs/2026-10-05-slskd-soulseek-design.md`（已批准）。

## Global Constraints

- 端口：WebUI 宿主 **8090** → 容器 5030；Soulseek 监听 **50300/tcp**（宿主=容器）。不得改动现有 22 / 8080 / 8899 / 45012。
- 镜像固定 `slskd/slskd:0.26.0`（不追 latest）。
- 凭据与状态（`slskd.env`、`slskd-config/`、`downloads/soulseek/`）只存在于运行环境，已在 `.gitignore`；**本计划与仓库文档一律零 IP、零账号名、零密码**（命令中用 `<VPS_IP>` 与"已商定中性用户名"表述）。
- 现有服务（qbittorrent / files）行为不得改变；`bootstrap.sh` 保持幂等。
- 提交信息统一以 `Co-Authored-By: Claude Code <noreply@anthropic.com>` 结尾。
- 环境事实（2026-10-05 核实）：slskd 最新稳定版 0.26.0；关键环境变量名：`SLSKD_SLSK_USERNAME` / `SLSKD_SLSK_PASSWORD` / `SLSKD_SLSK_LISTEN_PORT`、`SLSKD_USERNAME` / `SLSKD_PASSWORD`（WebUI 管理员）、`SLSKD_API_KEY`、`SLSKD_DOWNLOADS_DIR` / `SLSKD_INCOMPLETE_DIR`、`SLSKD_SHARED_DIR`（分号分隔）、`SLSKD_HTTP_PORT`、`SLSKD_REMOTE_CONFIGURATION`。

## 文件结构

| 动作 | 文件 | 职责 |
|---|---|---|
| Modify | `docker-compose.yml` | 新增 slskd 服务块 |
| Modify | `bootstrap.sh` | 幂等生成 `slskd.env` + 准备目录 |
| Modify | `backup-qb-config.sh` | 备份目标加入 slskd |
| Modify | `README.md` | Soulseek 章节 / 目录表 / 安全备注 |
| 运行时生成（不进仓库） | `slskd.env`、`slskd-config/`、`downloads/soulseek/` | 凭据与数据 |
| Modify（工作区，不进仓库） | `E:\pull-qb\CLAUDE.md` | 状态与常用操作 |
| Create（记忆） | `~/.claude/projects/E--pull-qb/memory/slskd-soulseek-setup.md` | 跨会话记忆 |

---

### Task 1: compose 新增 slskd 服务

**Files:** Modify: `docker-compose.yml`

**Interfaces:** Produces——服务名 `slskd`、`env_file: ./slskd.env`（Task 2 生成）、宿主端口 8090/50300（Task 6 验收依赖）。

- [ ] **Step 1: 在 `files:` 服务块之后新增（缩进与现有服务一致）**

```yaml
  slskd:
    image: slskd/slskd:0.26.0
    container_name: slskd
    restart: unless-stopped
    user: "1000:1000"
    env_file: ./slskd.env
    volumes:
      - ./slskd-config:/app
      - ./downloads:/downloads
    ports:
      - "8090:5030"        # WebUI（浏览器访问这个）
      - "50300:50300"      # Soulseek 监听口（公网可达）
```

- [ ] **Step 2: 语法检查（本机无 docker，用 Python 验 YAML）**

Run: `python -c "import yaml; yaml.safe_load(open('docker-compose.yml', encoding='utf-8')); print('YAML OK')"`
Expected: `YAML OK`

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: compose 新增 slskd 服务（WebUI 8090 / Soulseek 50300）"
```

### Task 2: bootstrap.sh 幂等生成 slskd.env 与目录

**Files:** Modify: `bootstrap.sh`（插在「免密拉取路径与哨兵」块之后、「定时任务」块之前）

**Interfaces:** Consumes——Task 1 的 `env_file: ./slskd.env` 契约；Produces——`slskd.env`（600 权限）与 `slskd-config/`、`downloads/soulseek/`（1000:1000）。

- [ ] **Step 1: 插入以下块（缩进与相邻块一致）**

```bash
# slskd（Soulseek）凭据与环境：首次生成并打屏一次（已存在则跳过）；模式同 .htpasswd
if [ ! -f slskd.env ]; then
  SLSK_USER="seedbox_$(openssl rand -hex 3)"
  SLSK_PASS=$(openssl rand -hex 10)
  WEB_PASS=$(openssl rand -hex 10)
  API_KEY=$(openssl rand -hex 16)
  umask 077
  cat > slskd.env <<ENVEOF
# slskd 配置与凭据（不进 git；随基线包迁移）
SLSKD_SLSK_USERNAME=$SLSK_USER
SLSKD_SLSK_PASSWORD=$SLSK_PASS
SLSKD_USERNAME=vj
SLSKD_PASSWORD=$WEB_PASS
SLSKD_API_KEY=$API_KEY
SLSKD_DOWNLOADS_DIR=/downloads/soulseek
SLSKD_INCOMPLETE_DIR=/downloads/soulseek/.incomplete
SLSKD_SHARED_DIR=/downloads/soulseek
SLSKD_SLSK_LISTEN_PORT=50300
SLSKD_HTTP_PORT=5030
SLSKD_REMOTE_CONFIGURATION=true
ENVEOF
  umask 022
  chmod 600 slskd.env
  echo "   slskd 凭据（请保存）: Soulseek=$SLSK_USER / $SLSK_PASS · WebUI=vj / $WEB_PASS · APIKey=$API_KEY"
fi
mkdir -p slskd-config downloads/soulseek downloads/soulseek/.incomplete
chown -R 1000:1000 slskd-config downloads/soulseek 2>/dev/null || true
```

说明：Soulseek 用户名默认 `seedbox_<随机>`，想改名就改 `slskd.env` 后首次启动（README 已写明）；`umask 077` 包裹生成保证 600，结束后恢复。
注意：`.incomplete` 目录必须**预建**——slskd 0.26.0 启动时校验其存在性，缺失即拒绝启动（2026-10-05 部署实测踩到）。

- [ ] **Step 2: 语法检查**

Run: `bash -n bootstrap.sh`
Expected: 无输出（语法 OK）

- [ ] **Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: bootstrap 生成 slskd 凭据与目录（幂等）"
```

### Task 3: 备份脚本覆盖 slskd

**Files:** Modify: `backup-qb-config.sh`（整体替换为下述内容）

**Interfaces:** Consumes——Task 2 的 `slskd-config/`、`slskd.env` 路径；Produces——备份 tgz 内含二者（Task 6 A8 验收）。

- [ ] **Step 1: 用以下内容替换整个脚本**

```bash
#!/usr/bin/env bash
# 每日备份配置与凭据（qB 配置与种子清单 + slskd 配置与凭据；不含下载数据）
# 产物: /root/qb-backups/qb-config-backup-<时间>.tgz，保留最近 7 份
# 部署：cron 例 "17 4 * * * /opt/seedbox-setup/backup-qb-config.sh >> /var/log/qb-backup.log 2>&1"
set -euo pipefail
DIR=/opt/seedbox-setup
OUT=/root/qb-backups
mkdir -p "$OUT"
TARGETS=(qb-config)
if [ -d "$DIR/slskd-config" ]; then TARGETS+=(slskd-config); fi
if [ -f "$DIR/slskd.env" ]; then TARGETS+=(slskd.env); fi
tar czf "$OUT/qb-config-backup-$(date +%Y%m%d-%H%M).tgz" \
  --exclude='qb-config/GeoDB' --exclude='qb-config/qBittorrent/logs' \
  --exclude='slskd-config/logs' \
  -C "$DIR" "${TARGETS[@]}"
ls -1t "$OUT"/qb-config-backup-*.tgz | tail -n +8 | xargs -r rm -f
```

- [ ] **Step 2: 语法检查**

Run: `bash -n backup-qb-config.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add backup-qb-config.sh
git commit -m "feat: 每日备份覆盖 slskd 配置与凭据"
```

### Task 4: README 更新

**Files:** Modify: `README.md`

- [ ] **Step 1: 「特性」列表在"每日备份"条之后追加**

```markdown
- **Soulseek 音乐下载**（slskd）：WebUI 8090 搜索/下载；文件自动进 8899 拉回管道；只分享自下载目录
```

- [ ] **Step 2: 「目录说明」表追加两行，并修改 downloads 行**

追加：

```markdown
| `slskd-config/` | slskd 配置与状态（**迁移时打包它**） |
| `slskd.env` | slskd 凭据（bootstrap 生成、打屏一次；不进 git） |
```

downloads 行改为：`| downloads/ | 下载 / 做种数据（含 slskd 的 downloads/soulseek/） |`

- [ ] **Step 3: 在「## 更新 EE 版本」之前插入新章节**

```markdown
## Soulseek（slskd）

做种机同时跑 [slskd](https://github.com/slskd/slskd)（Soulseek 网络的无头客户端），主攻公开 BT 上难得的老资源与无损音乐。

- WebUI：`http://<VPS_IP>:8090`（默认管理员 `vj`；密码在 `slskd.env`，首次 bootstrap 打屏一次）
- Soulseek 监听口：`50300`（TCP，公网可达；账号首次启动时自动注册，默认 `seedbox_<随机>`，想改就改 `slskd.env`）
- 下载落 `downloads/soulseek/`，自动出现在 8899 文件服务（basic auth 与免密路径均覆盖），拉回方式与 BT 完全一致
- 分享 = 只分享 `downloads/soulseek/`：你下载的音乐自动回馈网络（Soulseek 的互惠文化：有分享才能从别人处下载）
- API：请求头 `X-API-Key: <slskd.env 中的 SLSKD_API_KEY>`
- 升级：改 compose 中 `slskd/slskd:<版本>` 后 `docker compose up -d slskd`
```

- [ ] **Step 4: 「安全模型与免责」补一行**

```markdown
- slskd：WebUI 明文 HTTP + 强密码（与 8080/8899 同一权衡）；`slskd.env` 权限 600、不进仓库。
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: README 新增 Soulseek/slskd 章节"
```

### Task 5: 部署到 VPS

**Files:**（远端）`/opt/seedbox-setup/*`、（新建）`/opt/seedbox-setup/slskd.env`

**Interfaces:** Consumes——Task 1/2/3 的文件；Produces——运行中的 `slskd` 容器（Task 6 验收对象）。

- [ ] **Step 1: 上传更新文件（本地 Git Bash）**

```bash
cd E:/pull-qb
scp seedbox-setup/docker-compose.yml seedbox-setup/bootstrap.sh seedbox-setup/backup-qb-config.sh seedbox-setup/README.md root@<VPS_IP>:/opt/seedbox-setup/
```

- [ ] **Step 2: 在 VPS 写 `slskd.env`（用户名=部署前商定的中性名，不写入公开文档；密码现场生成、打屏一次保存）**

```bash
ssh root@<VPS_IP> 'bash -s' <<'EOF'
cd /opt/seedbox-setup
SLSK_USER="填：已商定中性用户名"
SLSK_PASS=$(openssl rand -hex 10)
WEB_PASS=$(openssl rand -hex 10)
API_KEY=$(openssl rand -hex 16)
umask 077
cat > slskd.env <<ENV
SLSKD_SLSK_USERNAME=$SLSK_USER
SLSKD_SLSK_PASSWORD=$SLSK_PASS
SLSKD_USERNAME=vj
SLSKD_PASSWORD=$WEB_PASS
SLSKD_API_KEY=$API_KEY
SLSKD_DOWNLOADS_DIR=/downloads/soulseek
SLSKD_INCOMPLETE_DIR=/downloads/soulseek/.incomplete
SLSKD_SHARED_DIR=/downloads/soulseek
SLSKD_SLSK_LISTEN_PORT=50300
SLSKD_HTTP_PORT=5030
SLSKD_REMOTE_CONFIGURATION=true
ENV
umask 022
chmod 600 slskd.env
echo "已写入。Soulseek=$SLSK_USER/$SLSK_PASS WebUI=vj/$WEB_PASS APIKey=$API_KEY"
EOF
```

- [ ] **Step 3: compose 校验（env_file 已存在、语法正常）**

Run: `ssh root@<VPS_IP> 'cd /opt/seedbox-setup && docker compose config -q && echo COMPOSE_OK'`
Expected: `COMPOSE_OK`

- [ ] **Step 4: 幂等部署**

Run: `ssh root@<VPS_IP> 'cd /opt/seedbox-setup && bash bootstrap.sh'`
Expected: 打印完成页（slskd.env 已存在会被跳过；qB/files 不受影响）

- [ ] **Step 5: 容器状态**

Run: `ssh root@<VPS_IP> 'cd /opt/seedbox-setup && docker compose ps'`
Expected: qbittorrent / files / slskd 三个均为 Up

- [ ] **Step 6: 确认已连上 Soulseek**

Run: `ssh root@<VPS_IP> 'docker logs slskd 2>&1 | tail -30'`
Expected: 出现登录/连接 Soulseek 的日志（含账号名）

### Task 6: 验收（8 条逐项实测，任何失败→修复→重验）

**回滚预案**：如需撤销，按 spec 回滚节操作（`docker compose stop slskd && docker compose rm -f slskd`，并从 compose 移除服务块）。

- [ ] **A1 容器与既有无损**：`ssh root@<VPS_IP> 'cd /opt/seedbox-setup && docker compose ps && docker top qbittorrent | grep -c qbittorrent-nox'` → 三服务 Up 且计数 ≥1。
- [ ] **A2 WebUI 外部可达（本机跑，走 Clash）**：`curl -x http://127.0.0.1:7890 -s -o /dev/null -w "%{http_code}\n" http://<VPS_IP>:8090/` → `200`。
- [ ] **A3 已连 Soulseek**：同 Task 5 Step 6 日志。
- [ ] **A4 搜索出结果（API，凭 X-API-Key，无需登录会话）**：

```bash
ssh root@<VPS_IP> 'bash -s' <<'EOF'
cd /opt/seedbox-setup; K=$(grep SLSKD_API_KEY slskd.env | cut -d= -f2)
# 0.26.0 生产构建不提供 swagger；以下端点已实测确认；对端不可达时入队会报 500 → 换用户重试
ID=$(curl -s -H "X-API-Key: $K" -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:8090/api/v0/searches -d '{"searchText":"Khalil Fong"}' \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
echo "search id: $ID"; sleep 12
curl -s -H "X-API-Key: $K" "http://127.0.0.1:8090/api/v0/searches/$ID" | python3 -c "
import json,sys; d=json.load(sys.stdin); rs=d.get('responses') or []
print('响应数:', len(rs)); [print(' ', r['username'], len(r.get('files') or []), 'files') for r in rs[:5]]"
EOF
```

Expected: 响应数 > 0（列出若干用户与文件数）。

- [ ] **A5 下载 + 8899 拉回**：从 A4 结果挑一个可下载的小文件（优先 CC 授权素材，如搜 "Kevin MacLeod"），发起下载：

```bash
# 在 VPS 上（K 同上）：
curl -s -H "X-API-Key: $K" -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:8090/api/v0/transfers/downloads/<username> \
  -d '[{"filename":"<完整文件名>","size":<字节数>}]'
```

等待文件出现在 `downloads/soulseek/`，再做 Range 测试（走免密路径，无需 files 密码）：

```bash
ssh root@<VPS_IP> "SECRET=\$(cat /opt/seedbox-setup/http-serve/.secret-path); curl -s -r 0-1023 -o /dev/null -w '%{http_code}\n' \"http://127.0.0.1:8899/\$SECRET/soulseek/<测试文件名>\""
```

Expected: `206`

- [ ] **A6 监听口外部可达（本机跑，直连不走代理）**：`python -c "import socket;s=socket.create_connection(('<VPS_IP>',50300),5);print('50300 open');s.close()"` → `50300 open`。
- [ ] **A7 重启恢复**：`ssh root@<VPS_IP> 'docker kill slskd; sleep 15; cd /opt/seedbox-setup && docker compose ps | grep slskd'` → 显示 Up（restart 策略生效）；再择空闲时段整机 `reboot` 复核一次（约 1 分钟中断做种，事先知会用户）。
- [ ] **A8 备份包含 slskd**：`ssh root@<VPS_IP> 'bash /opt/seedbox-setup/backup-qb-config.sh && tar tzf "$(ls -t /root/qb-backups/*.tgz | head -1)" | grep -c slskd'` → `≥2`（`slskd-config/` 与 `slskd.env`）。

### Task 7: 基线包重建与拉回

**Interfaces:** Consumes——部署完成的整套配置；Produces——`backups/seedbox-bundle-<日期>.tgz` 本地留底。

- [ ] **Step 1: VPS 打包**

```bash
ssh root@<VPS_IP> "cd /opt && tar czf /tmp/seedbox-bundle-\$(date +%Y%m%d-%H%M).tgz \
  --exclude='seedbox-setup/downloads' \
  --exclude='seedbox-setup/http-serve/secret-logs' \
  --exclude='seedbox-setup/qb-config/GeoDB' \
  --exclude='seedbox-setup/qb-config/qBittorrent/logs' \
  seedbox-setup && ls -lh /tmp/seedbox-bundle-*.tgz"
```

- [ ] **Step 2: 拉回本地**：`scp root@<VPS_IP>:/tmp/seedbox-bundle-*.tgz E:/pull-qb/backups/`
- [ ] **Step 3: 校验**：双侧 `sha256sum` 一致；`tar tzf <本地包> | grep slskd` → 含 `slskd-config/` 与 `slskd.env` 条目。
- [ ] **Step 4: 旧包治理**：本地 `backups/` 只保留最近 2 份。

### Task 8: 文档收尾（CLAUDE.md + 记忆 + 推送）

- [ ] **Step 1: 工作区 `E:\pull-qb\CLAUDE.md`**

「关键事实」新增小节（含真实 IP，此文件不公开）：

```markdown
### Soulseek / slskd（2026-10-05 部署）
- slskd（Soulseek 无头客户端）运行中：WebUI `http://<VPS_IP>:8090`（管理员 <用户名>，密码在 VPS 的 `/opt/seedbox-setup/slskd.env`）
- 监听口 50300 TCP 公网可达；账号中性名（见 slskd.env），首次启动自动注册
- 下载落 `downloads/soulseek/`，自动进 8899 拉回管道；分享=仅该目录
- 凭据：slskd.env（600、随基线包迁移、永不进 git）；镜像 pin slskd/slskd:0.26.0
```

「常用操作」新增：

```bash
# slskd 凭据查看: ssh root@<VPS_IP> 'cat /opt/seedbox-setup/slskd.env'
# slskd API（X-API-Key 免登录）: K=$(ssh root@<VPS_IP> 'grep SLSKD_API_KEY /opt/seedbox-setup/slskd.env' | cut -d= -f2); curl -s -H "X-API-Key: $K" http://<VPS_IP>:8090/api/v0/application
```

「下一步」勾掉本项并写明结果（验收 8 条全过）。

- [ ] **Step 2: 记忆更新**——新建 `~/.claude/projects/E--pull-qb/memory/slskd-soulseek-setup.md`（type: project；内容：用途、端口、凭据位置、分享策略、镜像版本、拉回路径、踩坑），并在 `MEMORY.md` 追加一行索引。
- [ ] **Step 3: 推送**——确保所有 commit 已推：`git push`（若报网络波动重试）。
- [ ] **Step 4: 向用户交付总结**（WebUI 地址、凭据获取方式、一次拉回示例、验收结果）。

---

## Self-Review 记录

- **Spec 覆盖**：spec 变更清单 7 项 → Task 1-5/7；验收 8 条 → Task 6；安全 → Constraints + Task 4 Step 4；回滚 → Task 6 开头预案。无遗漏。
- **占位符扫描**：唯一"待填"项为用户名（刻意不入公开文档，已注明"部署前商定"）；其余均为可执行命令与确切代码。
- **一致性**：环境变量名、路径（`downloads/soulseek`）、服务名（`slskd`）、端口对（8090:5030 / 50300:50300）在全部任务中一致；API 路径已实测确认（见执行记录）。

---

## 执行记录（2026-10-05，全部落地）

**验收结果**

| 项 | 结果 |
|---|---|
| A1 容器与既有无损 | ✅ 三容器 Up，qB 进程无损 |
| A2 WebUI 公网 | ✅ 200 |
| A3 已连 Soulseek | ✅ `Logged in to the Soulseek server as <SLSK账号>` |
| A4 搜索 | ✅ "Khalil Fong" 33 响应（含文件明细） |
| A5 下载 + 拉回 | ✅ 实下 CC 小文件 `Completed, Succeeded`（223.7 KB/s），落盘 `downloads/soulseek/`，免密路径 Range **206** |
| A6 监听口外部 | ✅ 50300 open（本机直连探测） |
| A7 自愈 | ✅ 宿主机直杀容器进程模拟崩溃 → 15 秒内自动重启并重连 |
| A8 备份 | ✅ 备份包含 25 个 slskd 条目（slskd-config/ + slskd.env） |

**执行中发现（已修复/已记录）**

1. `.incomplete` 目录必须预建（slskd 0.26.0 启动校验），bootstrap 已修复并回填本文档。
2. `docker kill` 属显式停止，`unless-stopped` 按 Docker 设计**不**重启显式停止的容器；自愈的正确测试 = 杀主进程（崩溃语义）→ 实测 15 秒自愈。
3. 0.26.0 生产构建无 swagger 端点；API 路径实测确认：`POST /api/v0/searches`、`GET /api/v0/searches/{id}?includeResponses=true`、`POST /api/v0/transfers/downloads/{username}`（JSON 体 `[{filename,size}]`）、`GET /api/v0/transfers/downloads/{username}`。
4. 对端用户偶发不可达（直连/间接均失败），入队 API 返回 500 → 多用户重试策略（实测第二用户即通）。
