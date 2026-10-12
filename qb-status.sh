#!/usr/bin/env bash
# 做种状态速查（部署验收 / 日常排障）：种子总览 + DHT 节点数；可选单个种子的 tracker 明细
# 用法: bash qb-status.sh                 # 总览 + DHT
#       bash qb-status.sh <hash前8位>     # 附加该种子的 tracker 明细（st: 2=正常 1=未联系 4=不可用）
set -uo pipefail
cd "$(dirname "$0")"
qbc() { docker compose exec -T qbittorrent curl -s "$@"; }

echo "=== 种子总览（state/progress/速率/S=做种数 L=连接数） ==="
qbc http://127.0.0.1:8080/api/v2/torrents/info | python3 -c 'import sys,json
for t in json.load(sys.stdin):
    print(" ", t["hash"][:8], "|", t["state"], "|", round(t["progress"]*100,2), "% | dl", round(t["dlspeed"]/1048576,2), "MB/s | up", round(t["upspeed"]/1048576,2), "MB/s | S:", t["num_seeds"], "L:", t["num_leechs"], "|", t["name"])'

echo "=== DHT 节点数 ==="
qbc http://127.0.0.1:8080/api/v2/sync/maindata | python3 -c 'import sys,json; s=json.load(sys.stdin)["server_state"]; print("  dht_nodes:", s.get("dht_nodes"))'

if [ $# -ge 1 ]; then
  FULL=$(qbc http://127.0.0.1:8080/api/v2/torrents/info | python3 -c 'import sys,json
h = sys.argv[1].lower()
print(next((t["hash"] for t in json.load(sys.stdin) if t["hash"].lower().startswith(h)), ""))' "$1")
  if [ -z "$FULL" ]; then echo "未找到 hash 以 $1 开头的种子"; exit 1; fi
  echo "=== tracker 明细（${FULL:0:8}，st: 2=正常 1=未联系 4=不可用） ==="
  qbc "http://127.0.0.1:8080/api/v2/torrents/trackers?hash=$FULL" | python3 -c 'import sys,json
for tr in json.load(sys.stdin):
    if tr["url"].startswith("**"): continue
    print("  st=%s peers=%-4s msg=%s | %s" % (tr["status"], tr["num_peers"], (tr["msg"] or "-"), tr["url"][:72]))'
fi
