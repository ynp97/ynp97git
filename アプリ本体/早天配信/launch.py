#!/usr/bin/env python3
"""既存サーバーを再利用し、なければ一度だけ起動する。"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

HERE = Path(__file__).resolve().parent
URL = 'http://127.0.0.1:19797'


def running():
    try:
        with urllib.request.urlopen(URL + '/api/health', timeout=1) as response:
            return json.load(response).get('app') == 'soten-broadcast'
    except Exception:
        return False


def start():
    if running():
        return
    agent = Path.home() / 'Library/LaunchAgents/local.ynp97.soten-broadcast.plist'
    if sys.platform == 'darwin' and agent.exists():
        # The socket activates the service. Never start a second server on this port.
        subprocess.run(['launchctl', 'bootstrap', f'gui/{os.getuid()}', str(agent)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(30):
            if running():
                return
            time.sleep(.2)
        raise SystemExit('早天配信サービスに接続できません。.runtime/server.log を確認してください。')
    runtime = HERE / '.runtime'
    runtime.mkdir(exist_ok=True)
    with (runtime / 'server.log').open('ab') as output:
        process = subprocess.Popen([sys.executable, str(HERE / 'server.py')], cwd=HERE,
                                   stdout=output, stderr=output, stdin=subprocess.DEVNULL,
                                   start_new_session=True)
    (runtime / 'server.pid').write_text(str(process.pid))
    for _ in range(40):
        if running():
            return
        if process.poll() is not None:
            break
        time.sleep(.15)
    raise SystemExit('起動できませんでした。早天配信/.runtime/server.log を確認してください。')


if __name__ == '__main__':
    start()
    if '--no-open' not in sys.argv:
        request = urllib.request.Request(URL + '/api/action', data=b'{"action":"open_today"}',
                                         headers={'Content-Type':'application/json','Origin':URL})
        with urllib.request.urlopen(request, timeout=5) as response:
            response.read()
        if sys.platform == 'darwin':
            subprocess.run(['open', '-a', 'OBS'], check=False)
            if '--browser' in sys.argv:
                subprocess.run(['open', '-a', 'Google Chrome', URL], check=False)
        else:
            import webbrowser
            webbrowser.open(URL)
    print(URL)
