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

# 定时任务（幂等）：qb-config 备份 + 免密路径哨兵
if command -v crontab >/dev/null 2>&1; then
  TMPC=$(mktemp)
  crontab -l 2>/dev/null | grep -vE 'backup-qb-config\.sh|secret-sentinel\.sh' > "$TMPC" || true
  [ -f backup-qb-config.sh ] && echo '17 4 * * * /opt/seedbox-setup/backup-qb-config.sh >> /var/log/qb-backup.log 2>&1' >> "$TMPC"
  [ -f secret-sentinel.sh ] && echo '23 4 * * * /opt/seedbox-setup/secret-sentinel.sh >> /var/log/secret-sentinel.log 2>&1' >> "$TMPC"
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
