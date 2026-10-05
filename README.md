# seedbox-setup — 做种机最小栈（qBittorrent Enhanced Edition）

在公网 VPS 上搭「BT 做种机 + 文件回传管道」的最小自托管栈。适合入站被封、本地没法做种，需要「公网下载/做种 → 拉回本地」的场景（校园网、CGNAT 家宽等）。

结构：**EE 官方静态二进制**（`ee/qbittorrent-nox`，挂载替换容器内原版）+ **linuxserver 容器壳**（负责系统依赖与自启）。
适用：CloudCone 小时实例 / 年付 VPS（Ubuntu 22.04+）。

## 特性

- **一键部署**（`bootstrap.sh`，幂等）：Docker、SSH 加固、EE 二进制、容器、cron 全部自动装好
- **换机迁移**：基线包 + bootstrap，配置/凭据/种子清单全带走（见「换机迁移」节）
- **文件回传**（8899）：Range 断点续传 + basic auth + 「URL 即凭据」免密随机路径
- **访问哨兵**：免密路径被访问时每日汇总、新 IP 标 ⚠️
- **每日备份**：qB 配置与种子清单自动打包（保留 7 份，含自动安全更新之外的兜底）
- **Soulseek 音乐下载**（slskd）：WebUI 8090 搜索/下载；文件自动进 8899 拉回管道；只分享自下载目录

## 用法（VPS 上）

```bash
# 1) 在你电脑上：取代码（git clone 或下载 zip）
git clone https://github.com/visionjam/seedbox-setup
# 2) 传到 VPS（Windows 自带 ssh/scp 即可）：
scp -r seedbox-setup root@<VPS_IP>:/opt/
# 3) 上机一键部署：
ssh root@<VPS_IP>
cd /opt/seedbox-setup && bash bootstrap.sh
```

- 浏览器打开 `http://<VPS_IP>:8080`，账号 `admin`；
  **首次密码**在日志里：`docker logs qbittorrent 2>&1 | grep -i "temporary password"`
  （登录后立刻改成自己的密码；不改的话每次重启会变）
- 做种端口 `45012`（TCP+UDP），已在 compose 与 qB 设置中一致。
- > 若运行报 `$'\r'` 错误（Windows 换行符）：先执行 `sed -i 's/\r$//' bootstrap.sh`

## 目录说明

| 路径 | 作用 |
|---|---|
| `docker-compose.yml` | 服务定义（含 EE 二进制挂载行） |
| `ee/qbittorrent-nox` | EE 官方静态二进制（bootstrap 自动下载；当前对应 EE release-5.2.4.10） |
| `qb-config/` | qB 配置（**迁移时打包它**） |
| `downloads/` | 下载 / 做种数据（含 slskd 的 downloads/soulseek/） |
| `slskd-config/` | slskd 配置与状态（**迁移时打包它**） |
| `slskd.env` | slskd 凭据（bootstrap 生成、打屏一次；不进 git） |
| `http-serve/` | 文件服务配置（nginx；回传拉取用，8899，basic auth） |

## 文件回传（VPS → 本地）

- compose 内置 `files` 服务（nginx）把 `downloads/` 挂在 **8899**：支持 Range、basic auth
  （`.htpasswd` 由 bootstrap 首次生成并打屏一次；忘了可删掉重建）。
- 本机拉回（Gopeed：URL 内嵌凭据 `http://files:<密码>@<VPS_IP>:8899/<文件名>` 即可，已实测；curl 示例）：

```bash
curl -x http://127.0.0.1:7890 -u 'files:<密码>' -C - -O 'http://<VPS_IP>:8899/<文件名>'
```

- 手机/任意设备：浏览器打开 8899 → 登录 → **长按文件「复制链接」**（得到编码好的路径）→ 前缀补 `files:<密码>@` 交给下载器；或直接点按用浏览器下载。
  例：复制得 `http://<VPS_IP>:8899/%5BANi%5D%20...mp4` → 下载器里改成 `http://files:<密码>@<VPS_IP>:8899/%5BANi%5D%20...mp4`（只在 `http://` 后插凭据，其余原样）。
- **免密拉取路径（可选，推荐）**：`bash rotate-secret-path.sh` 生成一条随机路径（`http://<VPS_IP>:8899/<随机段>/`）——**URL 即凭据**，Gopeed/浏览器零配置直连（复制即用，无需插密码）；疑似泄漏时重跑该脚本即刻换新（旧路径作废）。片段文件 `http-serve/secret-path.conf` 含机密、不进 git，但**随基线包迁移**。
- **访问哨兵**：`secret-sentinel.sh` 每日汇总免密路径访问来源（新 IP 标 ⚠️）→ `/root/secret-sentinel-digest.txt`；bootstrap 会自动装好两条 cron（备份 + 哨兵）。
- 提示：中文文件名先下 ASCII 临时名再改名；长下载断流用 `-C -` 续传。
- **线路会波动**：代理 / 直连谁快随时段翻转（实测出现过 30KB/s ↔ 2MB/s 的反转）；拉大文件前各测一次，批量拉回建议脚本化（4 并发 + `.part` 断点续传），中途换线无损、不重复下载。

## Soulseek（slskd）

做种机同时跑 [slskd](https://github.com/slskd/slskd)（Soulseek 网络的无头客户端），主攻公开 BT 上难得的老资源与无损音乐。

- WebUI：`http://<VPS_IP>:8090`（默认管理员 `vj`；密码在 `slskd.env`，首次 bootstrap 打屏一次）
- Soulseek 监听口：`50300`（TCP，公网可达；账号首次启动时自动注册，默认 `seedbox_<随机>`，想改就改 `slskd.env`）
- 下载落 `downloads/soulseek/`，自动出现在 8899 文件服务（basic auth 与免密路径均覆盖），拉回方式与 BT 完全一致
- 分享 = 只分享 `downloads/soulseek/`：你下载的音乐自动回馈网络（Soulseek 的互惠文化：有分享才能从别人处下载）
- API：请求头 `X-API-Key: <slskd.env 中的 SLSKD_API_KEY>`
- 升级：改 compose 中 `slskd/slskd:<版本>` 后 `docker compose up -d slskd`

## 手机通知（ntfy）

自建 [ntfy](https://ntfy.sh)（轻量推送服务）把 VPS 事件推到手机——无需 Google 服务、无需第三方账号。

- 服务端口：**8091**（宿主）；主题名存在 `ntfy-topic.txt`（600 权限，**主题名即密码**，不进 git、随基线包迁移与每日备份）
- 发送消息（任何脚本一行）：
  ```bash
  curl -d "✅ 下载完成" "http://127.0.0.1:8091/$(cat /opt/seedbox-setup/ntfy-topic.txt)"
  ```
- 手机订阅：装 ntfy App（Android：[binwiederhier/ntfy-android Releases](https://github.com/binwiederhier/ntfy-android/releases)；iOS：App Store）→ 添加服务器 `http://<VPS_IP>:8091` → 订阅主题（见 `ntfy-topic.txt`）
- Android 必做三项：电池→**无限制**、允许**自启动**、后台**锁定**（否则 90% 概率收不到推送）；iOS 对自建服务器需配置经 ntfy.sh 的 APNs 转发（见 ntfy 官方文档）
- **qB 完成钩子**：BT 种子下载完成自动推手机。脚本 `qb-config/hooks/torrent-finished.sh`（bootstrap 自动安装，主题随 qb-config 迁移）；启用：qB 设置 → 下载 → 「Run external program on torrent finished」填 `/bin/sh /config/hooks/torrent-finished.sh "%N"`（本栈部署时已由 API 启用，设置随 qb-config 备份恢复）
- **slskd 看门狗**（`slskd-watchdog.py`，bootstrap 自动装 cron，每 2 分钟）：专辑完成 ✅ / 失败 ⚠️ / 整批完成 🎉 自动推手机；状态文件防重复推送，slskd 重启自动重基线
- **qB 做种率看门狗**（`qb-watchdog.py`，cron 每 5 分钟）：任一 BT 种子分享率达到目标（默认 **2.0**，或该种子自设的 ratio limit）→ 推手机 🎯（每种子一次；自测：`python3 qb-watchdog.py --test`）
- **slskd 分享率账本**（`slskd-ratio-ledger.py`，cron 每 30 分钟）：跨重启累计 上传/下载 字节；**总体分享率达到 2.0 时推送并自动清理 `downloads/soulseek`**（清理前/后均会推手机；状态 `/root/slskd-ratio-state.json`，只清一次）
- 安全：服务端无账号体系，主题名即凭据；疑似泄漏时换新主题：`echo "vj-$(openssl rand -hex 6)" > ntfy-topic.txt && docker compose restart ntfy`（然后手机改订阅新主题）

## 更新 EE 版本

```bash
cd /opt/seedbox-setup/ee
curl -fL -o ee.zip "https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases/download/<新版本tag>/qbittorrent-enhanced-nox_x86_64-linux-musl_static.zip"
python3 -m zipfile -e ee.zip . && chmod +x qbittorrent-nox
cd .. && docker compose up -d --force-recreate qbittorrent
```
（发布页：https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases）

## 换机迁移（一键部署）

**准备物**：本地基线包 `backups/seedbox-bundle-<日期>.tgz`（含全部配置、凭据、种子清单、EE 二进制）

1. **新机装公钥**（唯一需要密码的一次，二选一）
   - 面板 Console（VNC）登录后粘：
     `mkdir -p ~/.ssh && echo '<你的公钥>' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`
   - 或本机：`ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<新IP>`
2. **传包**：`scp backups/seedbox-bundle-<日期>.tgz root@<新IP>:/opt/`
3. **解包 + bootstrap（全自动）**：
   `ssh root@<新IP> 'cd /opt && tar xzf seedbox-bundle-*.tgz && cd seedbox-setup && bash bootstrap.sh'`
   自动完成：装 Docker/btop → 识别已有 EE/凭据（跳过重复步骤）→ 关闭 SSH 密码登录 → 起 qB + files 容器
4. **数据**（二选一）
   - 常规：种子清单已恢复，数据从 swarm / 家里 qB 接力重新下载
   - 搬家：`ssh root@<旧机> 'tar czf - -C /opt/seedbox-setup downloads' | ssh root@<新IP> 'tar xzf - -C /opt/seedbox-setup'` → 全部「强制重新校验」
5. **验证**：`http://<新IP>:8080`（原 qB 密码）✓ · `http://<新IP>:8899`（files / 原密码）✓ · `ssh root@<新IP>` 免密 ✓ → 确认无误后再销毁旧机

**手工迁移（无基线包时）：** 新机 `scp -r seedbox-setup + bash bootstrap.sh` → 旧机 `qb-config/` 覆盖 → 种子全部「强制重新校验」→ 继续做种。

## 备注

- 若 EE 二进制下载失败，bootstrap 会生成 `docker-compose.noee.yml` 用原版启动（不影响可用性）。
- 验证 EE 是否生效：`docker compose exec qbittorrent qbittorrent-nox --version`（应显示 Enhanced Edition），或 WebUI 关于页。
- 反吸血：EE 内建屏蔽（迅雷/QQ/百度/Xfplay/DLBT、dt）+ `qb-config/qBittorrent/peer_blacklist.txt`（社区规则：anacrolix / dt / hp / xm / Gopeed-dev）；**放在 qBittorrent 子目录**（数据目录），改动后需重启 qB 生效，日志见 "contains N valid rules"；随 qb-config 备份与基线包迁移。
- FileBrowser 已于 2026-09 停止维护，本栈不含它；文件回传见上方「文件回传」节（内置 8899 文件服务）。
- 安全：试水期靠强密码即可；长期方案（SSH 隧道 / Tailscale）后续再加。
- 重启自愈：全部容器 `restart: unless-stopped`、docker/cron 开机自启（bootstrap 安装）——2026-10-05 实测确认；显式停止过的容器与种子保持停止；slskd 在途传输队列重启会丢（已完成文件不受影响）。

## 安全模型与免责

- 取舍：WebUI / 文件服务 = **强随机密码 + 明文 HTTP**（试水期方案；密码由 `bootstrap.sh` 现场生成，不写死）；SSH 仅密钥登录；免密路径可随时轮换（`rotate-secret-path.sh`，旧路径即时作废）。**长期建议：WebUI/SSH 收进 Tailscale/WireGuard 等隧道，公网只保留做种端口。**
- 本仓库刻意零凭据：`qb-config/`、`http-serve/.htpasswd`、`secret-path.conf`、`secret-logs/` 等运行时状态全部在 `.gitignore` 中；密码首次部署时生成并打屏一次。
- slskd：WebUI 明文 HTTP + 强密码（与 8080/8899 同一权衡）；`slskd.env` 权限 600、不进仓库。
- 本仓库只是自托管工具链；**请仅用于你有权下载与分享的内容**，使用风险自负。

## 许可

MIT，见 [LICENSE](LICENSE)。
