#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# qB 看门狗：BT 种子达到做种率（默认 2.0，或该种子的自定义 ratio limit）→ 手机 ntfy 推送
# cron（bootstrap 自动安装）：*/5 * * * * /usr/bin/python3 /opt/seedbox-setup/qb-watchdog.py >> /var/log/qb-watchdog.log 2>&1
# 每种子只推一次；种子删除后从记录剔除（重新添加可再次触发）
# 用法: python3 qb-watchdog.py [--test]
import json, os, subprocess, sys

DEFAULT_TARGET = 2.0
STATE = '/root/qb-watch-state.json'
TOPIC_FILE = '/opt/seedbox-setup/ntfy-topic.txt'
COMPOSE_DIR = '/opt/seedbox-setup'

TOPIC = open(TOPIC_FILE).read().strip()


def notify(msg, title='qB'):
    subprocess.run(['curl', '-s', '-m', '10', '-H', 'Title: ' + title, '-d', msg,
                    'http://127.0.0.1:8091/' + TOPIC], timeout=15)


def qb_torrents():
    out = subprocess.run(['docker', 'compose', 'exec', '-T', 'qbittorrent',
                          'curl', '-s', 'http://127.0.0.1:8080/api/v2/torrents/info'],
                         cwd=COMPOSE_DIR, stdin=subprocess.DEVNULL,
                         capture_output=True, text=True, timeout=60).stdout
    return json.loads(out) if out.strip() else []


def main():
    if '--test' in sys.argv:
        notify('🧪 qb-watchdog 测试推送：做种率事件通道正常', 'qB 测试')
        print('测试推送已发')
        return
    try:
        ts = qb_torrents()
    except Exception as e:
        print('qB API 失败（跳过本轮）:', e)
        return
    state = {'notified': []}
    if os.path.exists(STATE):
        try:
            state = json.load(open(STATE))
        except Exception:
            pass
    notified = set(state.get('notified') or [])
    current = {t.get('hash') for t in ts}
    notified &= current
    fired = []
    for t in ts:
        h = t.get('hash')
        if not h or h in notified:
            continue
        if (t.get('progress') or 0) < 1:
            continue
        ratio = t.get('ratio') or 0
        rl = t.get('ratio_limit') or -1
        target = rl if rl > 0 else DEFAULT_TARGET
        if ratio >= target:
            up_gb = (t.get('uploaded') or 0) / 2 ** 30
            notify('🎯 做种达标：%s｜分享率 %.2f（目标 %s）｜上传 %.2f GB｜可考虑清理腾空间'
                   % ((t.get('name') or '')[:40], ratio, target, up_gb), 'qB 做种达标')
            notified.add(h)
            fired.append(t.get('name'))
    json.dump({'notified': sorted(notified)}, open(STATE, 'w'))
    print('torrents=%d fired=%d' % (len(ts), len(fired)))
    for n in fired:
        print('  fired:', (n or '')[:60])


if __name__ == '__main__':
    main()
