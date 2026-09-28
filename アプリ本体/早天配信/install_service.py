#!/usr/bin/env python3
"""Install the per-user localhost socket service. OBS must be closed."""
import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import time
import urllib.request

LABEL = 'local.ynp97.soten-broadcast'
SOURCE = Path(__file__).resolve().parent
DEST = Path.home() / 'Desktop/AI関係/早天配信'
SERVICE = Path.home() / 'Library/Application Support/SotenBroadcast'

def install():
    if subprocess.run(['pgrep', '-x', 'OBS'], capture_output=True).returncode == 0:
        raise SystemExit('OBSを終了してから実行してください。')
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    backup = DEST / '設定控え' / ('service_' + stamp)
    backup.mkdir(parents=True)
    for name in ('server.py', 'launch.py', 'morning.py'):
        if (DEST / name).exists():
            shutil.copy2(DEST / name, backup / name)
    agent = Path.home() / 'Library/LaunchAgents' / (LABEL + '.plist')
    if agent.exists():
        shutil.copy2(agent, backup / agent.name)
    # Validate every existing listener before stopping or replacing anything.
    found = subprocess.run(['lsof', '-t', '-iTCP:19797', '-sTCP:LISTEN'], capture_output=True, text=True)
    pids = set(int(x) for x in found.stdout.split())
    for pid in pids:
        command = subprocess.check_output(['ps', '-p', str(pid), '-o', 'command='], text=True)
        if str(DEST / 'server.py') not in command and str(SERVICE / 'server.py') not in command and 'launchd' not in command:
            raise SystemExit('19797番ポートを別のプロセスが使用しています。変更していません。')
    domain = f'gui/{os.getuid()}'
    subprocess.run(['launchctl', 'bootout', domain + '/' + LABEL], capture_output=True)
    for pid in pids:
        try:
            if 'launchd' in subprocess.check_output(['ps', '-p', str(pid), '-o', 'command='], text=True):
                continue
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, subprocess.CalledProcessError):
            pass
    for name in ('server.py', 'launch.py', 'morning.py'):
        shutil.copy2(SOURCE / name, DEST / name)
    SERVICE.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE / 'server.py', SERVICE / 'server.py')
    shutil.copytree(SOURCE / 'web', SERVICE / 'web', dirs_exist_ok=True)
    if not (SERVICE / 'user_data').exists() and (DEST / 'user_data').exists():
        shutil.copytree(DEST / 'user_data', SERVICE / 'user_data')
    shutil.copy2(SOURCE / 'sync_data.py', DEST / 'sync_data.py')
    subprocess.run(['/usr/bin/python3', str(DEST / 'sync_data.py')], check=True)
    runtime = SERVICE / '.runtime'
    runtime.mkdir(exist_ok=True)
    config = {
        'Label': LABEL,
        'ProgramArguments': ['/usr/bin/python3', str(SERVICE / 'server.py'), '--launchd', '--vault', str(SERVICE / 'vault')],
        'WorkingDirectory': str(SERVICE),
        'Sockets': {'Listener': {'SockNodeName': '127.0.0.1', 'SockServiceName': '19797',
                                  'SockFamily': 'IPv4', 'SockType': 'stream'}},
        'ThrottleInterval': 2,
        'StandardOutPath': str(runtime / 'service.log'),
        'StandardErrorPath': str(runtime / 'service-error.log'),
    }
    agent.parent.mkdir(parents=True, exist_ok=True)
    with agent.open('wb') as f:
        plistlib.dump(config, f)
    agent.chmod(0o644)
    subprocess.run(['launchctl', 'bootstrap', domain, str(agent)], check=True)
    with urllib.request.urlopen('http://127.0.0.1:19797/api/health', timeout=15) as r:
        assert json.load(r)['app'] == 'soten-broadcast'
    print('Socket service ready. Backup:', backup)

if __name__ == '__main__':
    install()
