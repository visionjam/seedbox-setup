#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# slskd 看门狗：下载里程碑（专辑完成/失败/整批完成）→ 手机 ntfy 推送
# cron（bootstrap 自动安装）：*/2 * * * * /usr/bin/python3 /opt/seedbox-setup/slskd-watchdog.py >> /var/log/slskd-watchdog.log 2>&1
# 状态文件 /root/slskd-watch-state.json 防重复推送；slskd 重启（列表清空）时静默重基线
import json, os, subprocess, urllib.request

BASE = 'http://127.0.0.1:8090/api/v0'
STATE = '/root/slskd-watch-state.json'
TOPIC_FILE = '/opt/seedbox-setup/ntfy-topic.txt'
ENV_FILE = '/opt/seedbox-setup/slskd.env'


def load_key():
    for line in open(ENV_FILE):
        line = line.strip()
        if line.startswith('SLSKD_API_KEY='):
            return line.split('=', 1)[1]
    return ''


KEY = load_key()
TOPIC = open(TOPIC_FILE).read().strip()


def notify(msg, title='slskd'):
    try:
        subprocess.run(['curl', '-s', '-m', '10', '-H', 'Title: ' + title, '-d', msg,
                        'http://127.0.0.1:8091/' + TOPIC], timeout=15)
    except Exception as e:
        print('notify 失败:', e)


def api(path):
    r = urllib.request.Request(BASE + path)
    r.add_header('X-API-Key', KEY)
    with urllib.request.urlopen(r, timeout=30) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw.strip() else {}


def collect():
    entries = []

    def walk(x):
        if isinstance(x, list):
            for y in x:
                walk(y)
        elif isinstance(x, dict):
            if 'filename' in x and 'state' in x:
                entries.append(x)
            for y in x.values():
                walk(y)

    walk(api('/transfers/downloads'))
    return entries


def key_of(e):
    return (e.get('username') or '') + '|' + (e.get('filename') or '')


def lastdir(e):
    fn = (e.get('filename') or '').replace(chr(92), '/')
    parts = [p for p in fn.split('/') if p]
    return parts[-2] if len(parts) >= 2 else ''


def load_state():
    if os.path.exists(STATE):
        try:
            return json.load(open(STATE))
        except Exception:
            pass
    return {'init': False, 'done': [], 'err': [], 'dirs_done': []}


def save_state(done_keys, err_keys, full_dirs):
    json.dump({'init': True, 'done': sorted(done_keys), 'err': sorted(err_keys),
               'dirs_done': sorted(full_dirs)}, open(STATE, 'w'))


def main():
    try:
        entries = collect()
    except Exception as e:
        print('API 失败（跳过本轮）:', e)
        return
    st = load_state()
    if not entries:
        save_state([], [], [])
        print('无传输记录（可能已重启），静默重基线')
        return
    done, err, run = [], [], []
    for e in entries:
        s = str(e.get('state'))
        if ('Complet' in s) or ('Succeed' in s):
            done.append(e)
        elif ('Error' in s) or ('Cancel' in s) or ('Rejected' in s) or ('TimedOut' in s):
            err.append(e)
        else:
            run.append(e)
    done_keys = {key_of(e) for e in done}
    err_keys = {key_of(e) for e in err}
    dirs_total, dirs_done_n = {}, {}
    for e in entries:
        d = lastdir(e)
        if d:
            dirs_total[d] = dirs_total.get(d, 0) + 1
    for e in done:
        d = lastdir(e)
        if d:
            dirs_done_n[d] = dirs_done_n.get(d, 0) + 1
    full_dirs = {d for d, n in dirs_total.items() if dirs_done_n.get(d, 0) == n}
    prev_done = set(st.get('done') or [])
    prev_err = set(st.get('err') or [])
    prev_dirs = set(st.get('dirs_done') or [])

    if not st.get('init'):
        notify('👁️ slskd 通知已启用。当前进度：%d/%d 完成，%d 进行中' % (len(done), len(entries), len(run)),
               'slskd')
    else:
        for d in sorted(full_dirs - prev_dirs):
            notify('✅ 专辑完成：%s（%d 首）' % (d, dirs_total[d]), 'slskd 完成')
        for e in err:
            if key_of(e) not in prev_err:
                fn = (e.get('filename') or '').replace(chr(92), '/').split('/')[-1]
                notify('⚠️ 下载失败：%s' % fn[:60], 'slskd 失败')
        new_done = done_keys - prev_done
        if (not run) and new_done and done_keys:
            gb = sum((e.get('size') or 0) for e in done) / 2 ** 30
            notify('🎉 slskd 全部完成：%d 个文件 / %.2f GB' % (len(done), gb), 'slskd 完成')

    save_state(done_keys, err_keys, full_dirs)
    print('done=%d run=%d err=%d full_dirs=%d' % (len(done), len(run), len(err), len(full_dirs)))


if __name__ == '__main__':
    main()
