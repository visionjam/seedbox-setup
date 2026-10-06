#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# qB 看门狗（cron 每 5 分钟）→ 手机 ntfy 推送四类事件：
#   1) 种子做种率达标（默认 2.0，或该种子的自定义 ratio limit）——每种子只推一次
#   2) 新下载任务加入（⬇️）——首次运行只建立基线，不推送
#   3) 做种时长超过 24 小时（⏰）——每种子只推一次（可提醒清理）
#   4) （--test）测试推送
# 状态：/root/qb-watch-state.json；种子删除后从各记录剔除（重新添加可再次触发）
# 部署：cron "*/5 * * * * /usr/bin/python3 /opt/seedbox-setup/qb-watchdog.py >> /var/log/qb-watchdog.log 2>&1"
# 用法: python3 qb-watchdog.py [--test]
import json, os, subprocess, sys

DEFAULT_TARGET = 2.0
SEED_REMIND_S = 24 * 3600
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
        notify('🧪 qb-watchdog 测试推送：做种率 / 新任务 / 24 小时提醒 三条通道均正常', 'qB 测试')
        print('测试推送已发')
        return
    try:
        ts = qb_torrents()
    except Exception as e:
        print('qB API 失败（跳过本轮）:', e)
        return
    state = {'notified': [], 'known': [], 'seeded24': []}
    if os.path.exists(STATE):
        try:
            state = json.load(open(STATE))
        except Exception:
            pass
    current = {t.get('hash') for t in ts}
    notified = set(state.get('notified') or []) & current
    seeded24 = set(state.get('seeded24') or []) & current
    first_run = 'known' not in state
    known = set(state.get('known') or [])

    fired = []
    # 1) 新下载任务（首轮只建基线）
    if not first_run:
        for t in ts:
            h = t.get('hash')
            if h and h not in known:
                gb = (t.get('size') or 0) / 2 ** 30
                notify('⬇️ 新下载任务：%s｜%.2f GB' % ((t.get('name') or '')[:40], gb), 'qB 新任务')
                fired.append('new:' + (t.get('name') or ''))
    state['known'] = sorted(current)

    for t in ts:
        h = t.get('hash')
        if not h:
            continue
        # 2) 做种率达标
        if h not in notified and (t.get('progress') or 0) >= 1:
            ratio = t.get('ratio') or 0
            rl = t.get('ratio_limit') or -1
            target = rl if rl > 0 else DEFAULT_TARGET
            if ratio >= target:
                up_gb = (t.get('uploaded') or 0) / 2 ** 30
                notify('🎯 做种达标：%s｜分享率 %.2f（目标 %s）｜上传 %.2f GB｜可考虑清理腾空间'
                       % ((t.get('name') or '')[:40], ratio, target, up_gb), 'qB 做种达标')
                notified.add(h)
                fired.append('ratio:' + (t.get('name') or ''))
        # 3) 做种超 24 小时
        st = t.get('state') or ''
        if h not in seeded24 and 'UP' in st and (t.get('seeding_time') or 0) >= SEED_REMIND_S:
            hours = (t.get('seeding_time') or 0) / 3600
            ratio = t.get('ratio') or 0
            gb = (t.get('size') or 0) / 2 ** 30
            notify('⏰ 做种已超 24 小时：%s｜已种 %.0f 小时｜ratio %.2f｜%.2f GB｜可考虑清理腾空间'
                   % ((t.get('name') or '')[:40], hours, ratio, gb), 'qB 长时做种')
            seeded24.add(h)
            fired.append('24h:' + (t.get('name') or ''))

    json.dump({'notified': sorted(notified), 'known': state['known'],
               'seeded24': sorted(seeded24)}, open(STATE, 'w'))
    print('torrents=%d fired=%d first_run=%s' % (len(ts), len(fired), first_run))
    for n in fired:
        print('  fired:', n[:70])


if __name__ == '__main__':
    main()
