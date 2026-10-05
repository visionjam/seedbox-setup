#!/usr/bin/env bash
# 每日备份 qB 配置与种子（含 BT_backup/*.torrent；不含下载的数据文件）
# 产物: /root/qb-backups/qb-config-backup-<时间>.tgz，保留最近 7 份
# 部署：cron 例 "17 4 * * * /opt/seedbox-setup/backup-qb-config.sh >> /var/log/qb-backup.log 2>&1"
set -euo pipefail
DIR=/opt/seedbox-setup
OUT=/root/qb-backups
mkdir -p "$OUT"
tar czf "$OUT/qb-config-backup-$(date +%Y%m%d-%H%M).tgz" \
  --exclude='qb-config/GeoDB' --exclude='qb-config/qBittorrent/logs' \
  -C "$DIR" qb-config
ls -1t "$OUT"/qb-config-backup-*.tgz | tail -n +8 | xargs -r rm -f
