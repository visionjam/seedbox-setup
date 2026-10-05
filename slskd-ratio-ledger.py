#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# slskd 分享率账本：跨重启累计 上传/下载 字节；总体分享率 ≥ TARGET 时推送并自动清理 VPS 音乐副本
# cron（bootstrap 自动安装）：*/30 * * * * /usr/bin/python3 /opt/seedbox-setup/slskd-ratio-ledger.py >> /var/log/slskd-ratio-ledger.log 2>&1
# 状态：/root/slskd-ratio-state.json（含 deleted 标记，只清理一次）
import json, os, shutil, subprocess, urllib.request

TARGET = 2.0
AUTO_DELETE = True          # 用户政策（2026-10-05）：总体分享率达到 2 后删除 VPS 音乐副本（清理前先推手机）
SHARE_DIR = '/opt/seedbox-setup/downloads/soulseek'
STATE = '/root/slskd-ratio-state.json'
ENV_FILE = '/opt/seedbox-setup/slskd.env'
TOPIC_FILE = '/opt/seedbox-setup/ntfy-topic.txt'
MIN_DL = 100 * 1024 * 1024  # 下载量太小时不判达标（防除零/误判）

TOPIC = open(TOPIC_FILE).read().strip()
_K = ''
for _line in open(ENV_FILE):
    _line = _line.strip()
    if _line.startswith('SLSKD_API_KEY='):
        _K = _line.split('=', 1)[1]
BASE = 'http://127.0.0.1:8090/api/v0'


def notify(msg, title='slskd 账本'):
    subprocess.run(['curl', '-s', '-m', '10', '-H', 'Title: ' + title, '-d', msg,
                    'http://127.0.0.1:8091/' + TOPIC], timeout=15)


def req(path):
    r = urllib.request.Request(BASE + path)
    r.add_header('X-API-Key', _K)
    with urllib.request.urlopen(r, timeout=45) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw.strip() else {}


def collect(obj):
    out = []

    def rec(x):
        if isinstance(x, list):
            for y in x:
                rec(y)
        elif isinstance(x, dict):
            if 'filename' in x and 'state' in x:
                out.append(x)
            for y in x.values():
                rec(y)

    rec(obj)
    return out


def gb(b):
    return b / 2 ** 30


def main():
    try:
        ups = collect(req('/transfers/uploads'))
        dns = collect(req('/transfers/downloads'))
    except Exception as e:
        print('API 失败（跳过本轮）:', e)
        return
    ul_now = sum(e.get('bytesTransferred') or 0 for e in ups)
    dl_now = sum(e.get('bytesTransferred') or 0 for e in dns)
    run = 0
    for e in dns + ups:
        st = str(e.get('state'))
        if not ('Complet' in st or 'Succeed' in st or 'Error' in st or 'Cancel' in st or 'Rejected' in st or 'TimedOut' in st):
            run += 1

    st0 = {'ul_base': 0, 'dl_base': 0, 'ul_max': 0, 'dl_max': 0, 'deleted': False, 'init': False}
    if os.path.exists(STATE):
        try:
            st0 = json.load(open(STATE))
        except Exception:
            pass

    if not st0.get('init'):
        st0['init'] = True
        st0['ul_max'] = ul_now
        st0['dl_max'] = dl_now
        notify('📒 分享率账本上线：当前会话累计 上传 %.2f GB / 下载 %.2f GB。目标：总体分享率 ≥ %.1f 后自动清理 VPS 音乐副本（清理前会先推你）。'
               % (gb(ul_now), gb(dl_now), TARGET))
    else:
        if ul_now < st0['ul_max'] or dl_now < st0['dl_max']:
            st0['ul_base'] += st0['ul_max']
            st0['dl_base'] += st0['dl_max']
            st0['ul_max'] = ul_now
            st0['dl_max'] = dl_now
            print('检测到 slskd 重启，已归档上一会话：base_ul=%.2f GB base_dl=%.2f GB' % (gb(st0['ul_base']), gb(st0['dl_base'])))
        else:
            st0['ul_max'] = max(st0['ul_max'], ul_now)
            st0['dl_max'] = max(st0['dl_max'], dl_now)

    cum_ul = st0['ul_base'] + st0['ul_max']
    cum_dl = st0['dl_base'] + st0['dl_max']
    ratio = (cum_ul / cum_dl) if cum_dl > 0 else 0.0
    print('累计上传 %.3f GB / 累计下载 %.3f GB | ratio=%.4f | 在途=%d | deleted=%s'
          % (gb(cum_ul), gb(cum_dl), ratio, run, st0.get('deleted')))

    if (not st0.get('deleted')) and cum_dl >= MIN_DL and ratio >= TARGET and run == 0:
        freed = 0
        for root, dirs, files in os.walk(SHARE_DIR):
            if '.incomplete' in root:
                continue
            for f in files:
                try:
                    freed += os.path.getsize(os.path.join(root, f))
                except OSError:
                    pass
        notify('🏁 分享率达标（累计上传 %.2f GB ≥ %s×下载 %.2f GB，ratio=%.2f）。按政策开始清理 VPS 音乐副本…'
               % (gb(cum_ul), TARGET, gb(cum_dl), ratio), 'slskd 达标')
        removed = 0
        for name in os.listdir(SHARE_DIR):
            if name == '.incomplete':
                continue
            p = os.path.join(SHARE_DIR, name)
            try:
                if os.path.isdir(p):
                    shutil.rmtree(p)
                else:
                    os.remove(p)
                removed += 1
            except OSError as e:
                print('删除失败:', p, e)
        st0['deleted'] = True
        notify('✅ 已清理 %d 项、释放约 %.2f GB（分享目录已清空）。账本继续运行，后续下载将重新积累。'
               % (removed, gb(freed)), 'slskd 达标')

    json.dump(st0, open(STATE, 'w'))


if __name__ == '__main__':
    main()
