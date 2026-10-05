#!/usr/bin/env bash
# 做种机一键部署（Ubuntu / Debian，root 运行）
# 组件：qBittorrent-Enhanced-Edition（官方静态二进制）+ linuxserver 容器壳
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/4] 安装 Docker 与 btop（已装则跳过）..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
if ! docker compose version >/dev/null 2>&1 || ! command -v btop >/dev/null 2>&1; then
  apt-get update -y
fi
if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y docker-compose-plugin
fi
if ! command -v btop >/dev/null 2>&1; then
  apt-get install -y btop
fi
if ! command -v crontab >/dev/null 2>&1; then
  apt-get update -y >/dev/null && apt-get install -y cron >/dev/null && systemctl enable --now cron
fi

# SSH 加固：已有公钥时禁用密码登录（新机务必先装好公钥再跑 bootstrap；没装则自动跳过不锁死）
if [ -s /root/.ssh/authorized_keys ]; then
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/00-hardening.conf
  if sshd -t; then systemctl reload ssh 2>/dev/null || true; fi
fi

echo "[2/4] 下载 qBittorrent-Enhanced-Edition 静态二进制（失败则退回原版）..."
mkdir -p ee
if [ ! -f ee/qbittorrent-nox ]; then
  if curl -fL --retry 2 -m 300 -o /tmp/ee.zip \
     "https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases/download/release-5.2.4.10/qbittorrent-enhanced-nox_x86_64-linux-musl_static.zip"; then
    python3 -m zipfile -e /tmp/ee.zip ee/ && chmod +x ee/qbittorrent-nox && echo "   ✅ EE 二进制就绪"
  else
    echo "   ⚠️ EE 下载失败，本次将使用原版 qBittorrent"
  fi
fi
COMPOSE_FILE="docker-compose.yml"
if [ ! -f ee/qbittorrent-nox ]; then
  grep -v 'ee/qbittorrent-nox' docker-compose.yml > docker-compose.noee.yml
  COMPOSE_FILE="docker-compose.noee.yml"
fi

# 文件服务（8899）凭据：首次生成并打屏一次；忘记可删掉本文件重启 files 容器
mkdir -p http-serve
if [ ! -f http-serve/.htpasswd ]; then
  PASS_FILES=$(openssl rand -hex 6)
  printf 'files:%s\n' "$(openssl passwd -apr1 "$PASS_FILES")" > http-serve/.htpasswd
  echo "   文件服务(8899) 凭据: files / $PASS_FILES  （请保存）"
fi

# 免密拉取路径与哨兵（首次为空文件/空目录；启用或轮换: bash rotate-secret-path.sh）
mkdir -p http-serve/secret-logs
[ -f http-serve/secret-path.conf ] || : > http-serve/secret-path.conf

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
SLSKD_SHARE_CACHE_RETENTION=60
ENVEOF
  umask 022
  chmod 600 slskd.env
  echo "   slskd 凭据（请保存）: Soulseek=$SLSK_USER / $SLSK_PASS · WebUI=vj / $WEB_PASS · APIKey=$API_KEY"
fi
mkdir -p slskd-config downloads/soulseek downloads/soulseek/.incomplete
chown -R 1000:1000 slskd-config downloads/soulseek 2>/dev/null || true

# ntfy 通知：主题生成 + qB 完成钩子安装（幂等）
if [ ! -f ntfy-topic.txt ]; then
  echo "vj-$(openssl rand -hex 6)" > ntfy-topic.txt
  chmod 600 ntfy-topic.txt
  echo "   ntfy 主题（手机订阅用，请保存）: $(cat ntfy-topic.txt)"
fi
mkdir -p qb-config/hooks
cp -f ntfy-topic.txt qb-config/ntfy-topic.txt
cat > qb-config/hooks/torrent-finished.sh <<'HOOKEOF'
#!/bin/sh
# qB 下载完成钩子 → 手机推送（ntfy）。由 bootstrap 安装；主题随 qb-config 迁移。
NAME="${1:-未知任务}"
TOPIC=$(cat /config/ntfy-topic.txt 2>/dev/null)
[ -z "$TOPIC" ] && exit 0
curl -s -m 10 -d "✅ qB 下载完成：$NAME" "http://ntfy/$TOPIC" >/dev/null 2>&1
exit 0
HOOKEOF
chmod +x qb-config/hooks/torrent-finished.sh
chown -R 1000:1000 qb-config/hooks qb-config/ntfy-topic.txt 2>/dev/null || true

# 定时任务（幂等）：qb-config 备份 + 免密路径哨兵
if command -v crontab >/dev/null 2>&1; then
  TMPC=$(mktemp)
  crontab -l 2>/dev/null | grep -vE 'backup-qb-config\.sh|secret-sentinel\.sh|slskd-watchdog\.py|qb-watchdog\.py|slskd-ratio-ledger\.py' > "$TMPC" || true
  [ -f backup-qb-config.sh ] && echo '17 4 * * * /opt/seedbox-setup/backup-qb-config.sh >> /var/log/qb-backup.log 2>&1' >> "$TMPC"
  [ -f secret-sentinel.sh ] && echo '23 4 * * * /opt/seedbox-setup/secret-sentinel.sh >> /var/log/secret-sentinel.log 2>&1' >> "$TMPC"
  [ -f slskd-watchdog.py ] && echo '*/2 * * * * /usr/bin/python3 /opt/seedbox-setup/slskd-watchdog.py >> /var/log/slskd-watchdog.log 2>&1' >> "$TMPC"
  [ -f qb-watchdog.py ] && echo '*/5 * * * * /usr/bin/python3 /opt/seedbox-setup/qb-watchdog.py >> /var/log/qb-watchdog.log 2>&1' >> "$TMPC"
  [ -f slskd-ratio-ledger.py ] && echo '*/30 * * * * /usr/bin/python3 /opt/seedbox-setup/slskd-ratio-ledger.py >> /var/log/slskd-ratio-ledger.log 2>&1' >> "$TMPC"
  crontab "$TMPC"
  rm -f "$TMPC"
fi

echo "[3/4] 启动 qBittorrent ..."
docker compose -f "$COMPOSE_FILE" up -d

echo "[4/4] 完成"
IP=$(curl -fsS -m 8 https://api.ipify.org 2>/dev/null || echo "<在面板里看IP>")
cat <<EOF

=============================================
  qBittorrent WebUI : http://$IP:8080
  登录账号          : admin（首次密码见日志：docker logs qbittorrent 2>&1 | grep -i temporary）
  BT 做种端口       : 45012 TCP+UDP
  文件服务(拉回)    : http://$IP:8899（账号 files，密码见上方打屏）
  数据目录          : $(pwd)/downloads
  配置文件          : $(pwd)/qb-config（迁移时打包带走）
  EE 二进制         : $(pwd)/ee/qbittorrent-nox
=============================================
EOF
