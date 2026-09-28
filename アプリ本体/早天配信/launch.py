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


def morning_setup():
    """今日のPDFの受け渡しと画面配置。ここで失敗しても配信は起動する。"""
    try:
        import morning
    except ImportError:
        return None, None
    agent = Path.home() / 'Library/LaunchAgents/local.ynp97.soten-broadcast.plist'
    target = (morning.SERVICE if agent.exists() else HERE) / 'user_data'
    try:
        source = morning.stage_today_pdf(target)
        print('今日のPDF：', source if source else '見つかりません（ダウンロード・Vaultのoutput/pdf）')
    except Exception as error:
        print('今日のPDFを渡せませんでした：', error)
    try:
        layout = morning.plan(morning.screen_frame())
    except Exception as error:
        print('画面の大きさを取得できませんでした：', error)
        return morning, None
    if not morning.obs_running():
        note = morning.set_obs_geometry(layout['obs'], backup_dir=HERE / '設定控え')
        if note:
            print(note)
    return morning, layout


if __name__ == '__main__':
    if (HERE / 'sync_data.py').exists():
        subprocess.run([sys.executable, str(HERE / 'sync_data.py')], check=True)
    start()
    if '--no-open' not in sys.argv:
        request = urllib.request.Request(URL + '/api/action', data=b'{"action":"open_today"}',
                                         headers={'Content-Type':'application/json','Origin':URL})
        with urllib.request.urlopen(request, timeout=5) as response:
            response.read()
        if sys.platform == 'darwin':
            morning, layout = morning_setup()
            subprocess.run(['open', '-a', 'OBS'], check=False)
            opened = False
            if layout:
                try:
                    morning.open_reader(URL + '/reader', layout['reader'])
                    opened = True
                except Exception as error:
                    print('原稿画面を配置できませんでした：', getattr(error, 'stderr', '') or error)
            if not opened:
                subprocess.run(['open', '-a', 'Google Chrome', URL + '/reader'], check=False)
        else:
            import webbrowser
            webbrowser.open(URL)
    print(URL)
