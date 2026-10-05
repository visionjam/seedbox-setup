# slskd（Soulseek）接入设计 — 2026-10-05

> 状态：已经用户批准（2026-10-05 对话）。实现落在 seedbox-setup 主仓库。
> 公开纪律：本文档不含任何真实 IP、账号名与凭据。

## 背景与目标

音乐类老资源（如华语无损全集）在公开 BT 上活性极低；Soulseek 是音乐 P2P 的主阵地，slskd 是其无头客户端（Docker + WebUI）。

**目标**：把 slskd 并入现有做种机栈，打通与 BT 一致的闭环：
搜索 → 下载到 VPS → 自动出现在 8899 文件服务（basic auth + 免密路径）→ 走现有拉回管道到本地。

**非目标（YAGNI）**：WebUI 反代/子路径；音乐库自动整理；把本地音乐库上传到 VPS 分享；自动追专辑（Soulseek 是交互式搜索，无 RSS 生态）。

## 架构

- **方案 A（已选定）**：在现有 `docker-compose.yml` 中新增 `slskd` 服务，与 qBittorrent、files 同栈管理。
  （备选：B 独立 compose 项目——两套备份/迁移/文档，收益不值；C `docker run` 手搓——脱离既有体系。均否决。）
- **数据流**：
  - 浏览器 → WebUI（宿主 **8090** → 容器 5030，强密码）
  - slskd ↔ Soulseek 网络（监听口 **50300/TCP**，公网可达）
  - 下载落盘 `downloads/soulseek/`（未完成在 `.incomplete` 子目录）——该路径位于 nginx `files` 容器（8899）挂载范围内，**自动可拉回**，无需任何管道改动
  - **分享 = 只分享 `downloads/soulseek/` 本身**：自己下载的音乐自动回馈网络，零额外磁盘占用
- **状态与凭据**（均不进仓库、随基线包迁移）：
  - `slskd-config/`：容器 `/app` 挂载，服务状态
  - `slskd.env`：bootstrap 生成（Soulseek 账号密码 + WebUI 密码，打屏一次），compose 以 `env_file` 引用
  - Soulseek 用户名：部署时按「中性、不与公开身份关联」原则填写；**不写入仓库文档**

## 端口

| 端口 | 用途 | 备注 |
|---|---|---|
| 8090 | slskd WebUI（HTTP + 强密码） | 与 8080/8899 同风格；长期随隧道方案收编 |
| 50300/TCP | Soulseek 监听口 | 接收其他用户直连，提升下载来源 |

现有占用：22 / 8080 / 8899 / 45012——无冲突。

## 变更清单（实施时执行）

1. `docker-compose.yml`：新增 slskd 服务（固定镜像版本 tag；`env_file: ./slskd.env`；`restart: unless-stopped`）
2. `bootstrap.sh`：幂等步骤——首次生成 `slskd.env` 并打屏一次（模式与 .htpasswd 一致）
3. `backup-qb-config.sh`：扩展为同时打包 `slskd-config/`（脚本名保留，避免改 cron 行）
4. `README.md`：新增 slskd 章节（部署、使用、分享策略、安全说明）
5. 工作区 `CLAUDE.md`（不进仓库）：状态、常用操作更新
6. 基线包重建：`backups/seedbox-bundle-<日期>.tgz`（含 slskd-config + slskd.env），拉回本地校验
7. 部署到 VPS：scp 更新文件 → `bash bootstrap.sh`（幂等；自动生成 `slskd.env`、刷新 cron）→ `docker compose up -d`（仅新增服务，不影响现有服务）

## 验收标准（部署后逐条实测）

1. `docker compose ps`：slskd 运行中；qBittorrent / files 不受影响
2. `http://<VPS_IP>:8090` 公网可达、可登录
3. slskd 状态页显示已连接 Soulseek 网络（账号注册成功）
4. 搜索 "Khalil Fong" / "方大同" 返回真实用户结果
5. 下载一张小专辑 → 文件出现在 `downloads/soulseek/` → 8899（basic auth 与免密路径两条都测）Range 拉回
6. 50300 端口外部可达（他人可连入）
7. VPS 重启后 slskd 自动恢复
8. 每日备份产物包含 slskd-config

## 安全

- WebUI：强随机密码（bootstrap 生成、打屏一次）；明文 HTTP——与现有 8080/8899 同一权衡，长期由 Tailscale/WireGuard 方案统一收编
- Soulseek 账号独立凭据，不复用其他服务
- 分享目录只含自己下载的音乐
- `slskd-config/`、`slskd.env` 永久 gitignore，延续公开仓库零凭据原则

## 回滚

```bash
cd /opt/seedbox-setup
docker compose stop slskd && docker compose rm -f slskd
# 从 docker-compose.yml 移除服务块；按需删除 slskd-config/ slskd.env downloads/soulseek/
```
