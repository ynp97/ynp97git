#!/usr/bin/env python3
"""OBS終了中に実行。一度だけ試作用シーンを追加し、元ファイルを保存する。"""
import copy
import datetime
import json
from pathlib import Path
import plistlib
import shutil
import uuid

SOURCE = Path(__file__).resolve().parent
DEST = Path.home() / 'Desktop/AI関係/早天配信'
SCENE_NAME = '早天・日付で準備'
INPUT_NAME = '聖書（日付から自動）'


def install():
    DEST.mkdir(parents=True, exist_ok=True)
    for name in ('server.py', 'launch.py', '早天配信.command', 'README.md'):
        if (SOURCE / name).exists():
            shutil.copy2(SOURCE / name, DEST / name)
    shutil.copytree(SOURCE / 'web', DEST / 'web', dirs_exist_ok=True)
    bundle = DEST / '早天配信.app/Contents'
    (bundle / 'MacOS').mkdir(parents=True, exist_ok=True)
    with (bundle / 'Info.plist').open('wb') as output:
        plistlib.dump({'CFBundleIdentifier':'local.ynp97.soten-broadcast', 'CFBundleName':'早天配信',
                      'CFBundleDisplayName':'早天配信', 'CFBundleExecutable':'start',
                      'CFBundlePackageType':'APPL', 'CFBundleVersion':'1.0', 'LSUIElement':True}, output)
    executable = bundle / 'MacOS/start'
    executable.write_text('#!/bin/zsh\nAPP_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"\nexec /usr/bin/open -a Terminal "$APP_DIR/早天配信.command"\n')
    executable.chmod(0o755)
    (DEST / '早天配信.command').chmod(0o755)

    path = Path.home() / 'Library/Application Support/obs-studio/basic/scenes/早天.json'
    data = json.loads(path.read_text())
    if any(s['name'] == SCENE_NAME for s in data['sources']):
        print('アプリ更新。既存の試作用シーンは変更しません。')
        return
    source_scene = next(s for s in data['sources'] if s['id'] == 'scene' and s['name'] == data['current_scene'])
    backup = DEST / '設定控え'
    backup.mkdir(exist_ok=True)
    shutil.copy2(path, backup / ('早天_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '.json'))
    browser = copy.deepcopy(source_scene)
    browser.update(name=INPUT_NAME, uuid=str(uuid.uuid4()), id='browser_source', versioned_id='browser_source',
                   hotkeys={}, muted=True, mixers=0,
                   settings={'url':'http://127.0.0.1:19797/display?obs=1', 'width':1920, 'height':1080,
                             'fps':30, 'is_local_file':False, 'restart_when_active':True,
                             'shutdown':False, 'webpage_control_level':0,
                             'css':'body { background-color: rgba(0, 0, 0, 0); margin: 0px auto; overflow: hidden; }'})
    scene = copy.deepcopy(source_scene)
    scene.update(name=SCENE_NAME, uuid=str(uuid.uuid4()), hotkeys={'OBSBasic.SelectScene':[]})
    types = {s['uuid']:s['id'] for s in data['sources']}
    # カメラ・既存音声の参照は維持。PPのウィンドウキャプチャだけを新シーンから外す。
    scene['settings']['items'] = [i for i in scene['settings']['items'] if types.get(i.get('source_uuid')) != 'window_capture']
    item = copy.deepcopy(source_scene['settings']['items'][0])
    item.update(name=INPUT_NAME, source_uuid=browser['uuid'], visible=True, locked=True, rot=0.0,
                id=scene['settings']['id_counter']+1, pos={'x':0.0,'y':0.0},
                pos_rel={'x':-1.7777777777777777,'y':-1.0},
                scale={'x':1.0,'y':1.0}, scale_rel={'x':1.0,'y':1.0},
                crop_left=0,crop_right=0,crop_top=0,crop_bottom=0,
                bounds_type=0,bounds={'x':0.0,'y':0.0},bounds_rel={'x':0.0,'y':0.0})
    scene['settings']['items'].append(item)
    scene['settings']['id_counter']=item['id']
    data['sources'].extend([browser,scene])
    data['scene_order'].append({'name':SCENE_NAME})
    data['current_scene']=data['current_program_scene']=SCENE_NAME
    temporary=path.with_suffix('.json.soten-tmp')
    temporary.write_text(json.dumps(data,ensure_ascii=False,indent=2))
    temporary.replace(path)
    print('アプリ配置：',DEST)
    print('OBSシーン追加：',SCENE_NAME)
    print('元のシーンと音声設定は一致：', source_scene in data['sources'])


if __name__ == '__main__':
    install()
