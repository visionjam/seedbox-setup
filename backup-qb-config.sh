#!/usr/bin/env bash
# 每日备份配置与凭据（qB 配置与种子清单 + slskd 配置与凭据；不含下载数据）
# 产物: /root/qb-backups/qb-config-backup-<时间>.tgz，保留最近 7 份
# 完成/失败均推手机 ntfy（2026-10-06 加）
# 部署：cron 例 "17 4 * * * /opt/seedbox-setup/backup-qb-config.sh >> /var/log/qb-backup.log 2>&1"
set -uo pipefail
DIR=/opt/seedbox-setup
OUT=/root/qb-backups
TOPIC=$(cat "$DIR/ntfy-topic.txt" 2>/dev/null || true)

notify() { [ -n "$TOPIC" ] && curl -s -m 10 -H "Title: $1" -d "$2" "http://127.0.0.1:8091/$TOPIC" >/dev/null 2>&1 || true; }

mkdir -p "$OUT"
TARGETS=(qb-config)
[ -d "$DIR/slskd-config" ] && TARGETS+=(slskd-config)
[ -f "$DIR/slskd.env" ] && TARGETS+=(slskd.env)
[ -f "$DIR/ntfy-topic.txt" ] && TARGETS+=(ntfy-topic.txt)

NAME="qb-config-backup-$(date +%Y%m%d-%H%M).tgz"
if tar czf "$OUT/$NAME" \
     --exclude='qb-config/GeoDB' --exclude='qb-config/qBittorrent/logs' \
     --exclude='qb-config/qBittorrent/ipc-socket' \
     --exclude='slskd-config/logs' \
     -C "$DIR" "${TARGETS[@]}"; then
  SZ=$(du -h "$OUT/$NAME" | cut -f1)
  notify "备份完成" "✅ 每日备份完成：$NAME（$SZ）"
else
  notify "备份失败" "❌ 每日备份失败！查 /var/log/qb-backup.log；产物 $NAME 可能不完整"
  exit 1
fi
ls -1t "$OUT"/qb-config-backup-*.tgz | tail -n +8 | xargs -r rm -f
