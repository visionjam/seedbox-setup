#!/bin/bash
# SSH 新登录提醒（部署到 /etc/ssh/sshrc，任何失败都不得影响登录）
#  - 仅对"从未见过的来源 IP"推送（同一 IP 只提示一次，之后静默）
#  - sftp 子系统（新版 scp）不经过本脚本；ssh 命令/交互登录会经过
IP="${SSH_CONNECTION%% *}"
[ -z "$IP" ] && exit 0
SEEN=/root/.ssh-seen-ips.txt
touch "$SEEN" 2>/dev/null || exit 0
if ! grep -q "^$IP " "$SEEN" 2>/dev/null; then
  echo "$IP $(date -u '+%F %T') UTC" >> "$SEEN"
  TOPIC=$(cat /opt/seedbox-setup/ntfy-topic.txt 2>/dev/null)
  [ -n "$TOPIC" ] && curl -s -m 8 -H "Title: SSH 新登录" \
    -d "🔐 SSH 登录：新来源 IP $IP（用户 $USER，UTC $(date -u '+%F %T')）" \
    "http://127.0.0.1:8091/$TOPIC" >/dev/null 2>&1
fi
exit 0
