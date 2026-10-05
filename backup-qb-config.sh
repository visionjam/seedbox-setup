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
if [ -f "$DIR/ntfy-topic.txt" ]; then TARGETS+=(ntfy-topic.txt); fi
tar czf "$OUT/qb-config-backup-$(date +%Y%m%d-%H%M).tgz" \
  --exclude='qb-config/GeoDB' --exclude='qb-config/qBittorrent/logs' \
  --exclude='slskd-config/logs' \
  -C "$DIR" "${TARGETS[@]}"
ls -1t "$OUT"/qb-config-backup-*.tgz | tail -n +8 | xargs -r rm -f
