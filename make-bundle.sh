#!/usr/bin/env bash
# 全量基线包（换机迁移 / 备份用）：把 /opt/seedbox-setup 整包打成 /root/seedbox-bundle-<时间>.tgz
# 含：qb-config（种子清单/设置/反吸血/完成钩子）、slskd-config 与 slskd.env（凭据）、
#     ntfy-topic.txt、http-serve 机密（.htpasswd / secret-path.conf）、EE 二进制、全部脚本
# 不含：downloads/（数据单独处理。注意 http-serve 机密只在全量包里，每日备份不含）
# 产物 600 权限（内含明文凭据）；拉回与校验见 README「换机迁移」
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="/root/seedbox-bundle-$(date +%Y%m%d-%H%M).tgz"
umask 077
tar czf "$OUT" -C "$(dirname "$DIR")" --exclude="$(basename "$DIR")/downloads" "$(basename "$DIR")"
echo "产物: $OUT  ($(du -h "$OUT" | cut -f1), 权限 600)"
sha256sum "$OUT"
