#!/usr/bin/env bash
# 轮换「免密拉取路径」：生成新随机路径，旧路径立即作废（首次启用也跑这个）
# 注意：本脚本生成的 secret-path.conf 含机密，不进 git；随基线包迁移。
set -euo pipefail
DIR=/opt/seedbox-setup
CONF="$DIR/http-serve/secret-path.conf"
NEW=$(openssl rand -hex 6)
mkdir -p "$DIR/http-serve/secret-logs"
cat > "$CONF" <<EOF
# 免密拉取路径（URL 即凭据；本文件含机密、不进 git，随基线包迁移）
location /$NEW/ {
    alias /srv/;
    auth_basic off;
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;
    charset utf-8;
    access_log /var/log/secret/access.log;
}
EOF
chmod 600 "$CONF"
echo "$NEW" > "$DIR/http-serve/.secret-path"
chmod 600 "$DIR/http-serve/.secret-path"
cd "$DIR"
docker compose exec -T files nginx -t
docker compose exec -T files nginx -s reload
IP=$(curl -fsS -m 8 https://api.ipify.org 2>/dev/null || echo "<VPS_IP>")
echo "✅ 新免密路径: http://$IP:8899/$NEW/  （旧路径已作废，记得更新书签）"
