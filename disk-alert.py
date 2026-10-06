#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 磁盘低位告警：根分区剩余 < 2GB → 手机 ntfy 推送
#  - 降至阈值只推一次；回升到 2.5GB 以上重新武装；持续低位每 6 小时重提醒一次
# cron（bootstrap 自动安装）：*/15 * * * * /usr/bin/python3 /opt/seedbox-setup/disk-alert.py >> /var/log/disk-alert.log 2>&1
# 用法: python3 disk-alert.py [--test]
import json, os, shutil, subprocess, sys, time

THRESHOLD_MB = 2000
REARM_MB = 2500
REPEAT_S = 6 * 3600
STATE = '/root/disk-alert-state.json'
TOPIC_FILE = '/opt/seedbox-setup/ntfy-topic.txt'


def notify(msg, title='磁盘告警'):
    topic = open(TOPIC_FILE).read().strip()
    subprocess.run(['curl', '-s', '-m', '10', '-H', 'Title: ' + title, '-d', msg,
                    'http://127.0.0.1:8091/' + topic], timeout=15)


def main():
    usage = shutil.disk_usage('/')
    free_mb = usage.free // 2 ** 20
    if '--test' in sys.argv:
        notify('🧪 disk-alert 测试推送：磁盘告警通道正常（当前剩余 %d MB）' % free_mb)
        print('测试推送已发')
        return
    used_pct = 100 - free_mb * 2 ** 20 * 100 // usage.total
    state = {'armed': True, 'last': 0}
    if os.path.exists(STATE):
        try:
            state = json.load(open(STATE))
        except Exception:
            pass
    if free_mb >= REARM_MB:
        state['armed'] = True
    elif free_mb < THRESHOLD_MB:
        if state.get('armed') or time.time() - (state.get('last') or 0) > REPEAT_S:
            notify('⚠️ VPS 磁盘剩余 %d MB（低于 %d MB 阈值，已用 %d%%）。'
                   '可清理 downloads/soulseek 或扩容。' % (free_mb, THRESHOLD_MB, used_pct))
            state['armed'] = False
            state['last'] = time.time()
            print('alert fired: free_mb=%d' % free_mb)
    json.dump(state, open(STATE, 'w'))
    print('free_mb=%d armed=%s' % (free_mb, state.get('armed')))


if __name__ == '__main__':
    main()
