#!/usr/bin/env bash
# 哨兵：汇总「免密拉取路径」的访问来源；首次见到的 IP 标 ⚠️
# 产物：/root/secret-sentinel-digest.txt（随时可看）；状态：/root/secret-sentinel-seen.txt
set -uo pipefail
DIR=/opt/seedbox-setup
LOG="$DIR/http-serve/secret-logs/access.log"
STATE=/root/secret-sentinel-seen.txt
OUT=/root/secret-sentinel-digest.txt
touch "$STATE"
{
  echo "== 免密路径访问汇总（$(date '+%F %T')）=="
  if [ ! -s "$LOG" ]; then
    echo "（暂无访问记录）"
  else
    grep -oE '^[0-9a-fA-F.:]+' "$LOG" | sort | uniq -c | sort -rn | while read -r cnt ip; do
      if grep -qx "$ip" "$STATE" 2>/dev/null; then
        printf '   %s（%s 次）\n' "$ip" "$cnt"
      else
        echo "$ip" >> "$STATE"
        printf '⚠️ 新 %s（%s 次）\n' "$ip" "$cnt"
      fi
    done
    echo "-- 最近 3 条明细 --"
    tail -3 "$LOG"
    # 防膨胀：超过 1MB 时只留最近 2000 行
    if [ "$(stat -c %s "$LOG")" -gt 1048576 ]; then
      tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
  fi
} > "$OUT" 2>&1
cat "$OUT"
