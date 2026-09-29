import os, re, subprocess, datetime, urllib.parse, collections
H=os.path.expanduser("~")
ONMAC=os.path.isdir("/Volumes") and os.path.isdir("/Users/yoshiakinagumo")
def loc(mac, vm): return mac if ONMAC else vm
U="/Users/yoshiakinagumo"
ROOTS=[ # label, scan dir (local), real path prefix, local prefix, cloud?
 ("BENJAMIN（外付けSSD）", loc("/Volumes/BENJAMIN", H+"/mnt/BENJAMIN"), "/Volumes/BENJAMIN", False,
   ["_移行データ"]),
 ("OneDrive", loc(U+"/Library/CloudStorage/OneDrive-個人用", H+"/mnt/CloudStorage/OneDrive-個人用"), U+"/Library/CloudStorage/OneDrive-個人用", True,
   ["."]),
 ("iCloud Drive", loc(U+"/Library/Mobile Documents/com~apple~CloudDocs", H+"/mnt/com~apple~CloudDocs"), U+"/Library/Mobile Documents/com~apple~CloudDocs", True,
   ["Desktop", "Documents"]),
]
AUD=('.wav','.mp3','.aif','.aiff','.m4a','.flac')
MID=('.mid','.midi')
SKIPD={'Audio','Edits','Images','FREEVSTS','06_書籍・マンガ','Final Cut Original Media','Freeze','Auto Saves','superwhisper',
 'Native Instruments','BFD Drums','IK Multimedia','iZotope','Steinberg','Universal Audio','SYNTHS','Excite Audio','Evabeat','Crow Hill',
 'W.A.Production','ToneEmpire','SoundeviceDigital','PSPaudioware.com','Safari Pedals','Pro Tools','Accordance Files','Adobe','Codex','steinberg download','Track Pictures','MP3_1','放送大学','！ＤＴＭ　ＳＯＦＴ＿楽器系','！！本','COMICS','!!!!!!!!MOVIES','WB Games','!!PROG','ビートルズマイナス','AUてんこ盛り','Adobe Premiere Pro Audio Previews','Adobe Premiere Pro Video Previews'}
STEM=re.compile(r' - \d{4} - ')
def d(t): return datetime.datetime.fromtimestamp(t).strftime('%Y-%m-%d')
def dur(p):
    try:
        s=float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',p],capture_output=True,text=True,timeout=20).stdout.strip())
        return f"（{int(s//60)}:{int(s%60):02d}）"
    except: return ""
out=[];summary=[]
body=[]
for label,root,real,cloud,subs in ROOTS:
    if not os.path.isdir(root):
        summary.append(f"- **{label}**: このMacからは見えない（未接続）"); continue
    songs=collections.defaultdict(lambda:{'prj':[],'mix':[],'mid':[]})
    for sub in subs:
        base=os.path.join(root,sub)
        top_only = False
        for dp,dn,fn in os.walk(base):
            prj_dirs=[x for x in dn if x.lower().endswith('.logicx')]
            for x in prj_dirs:
                p=os.path.join(dp,x); songs[dp]['prj'].append((os.stat(p).st_mtime,x,p))
            if top_only: dn[:]=[]
            else: dn[:]=[x for x in dn if x not in SKIPD and not x.startswith('.') and not x.lower().endswith(('.logicx','.band'))]
            if top_only: 
                for f in fn:
                    if f.lower().endswith('.cpr'):
                        p=os.path.join(dp,f); songs[dp]['prj'].append((os.stat(p).st_mtime,f,p))
                continue
            for f in fn:
                l=f.lower(); p=os.path.join(dp,f)
                if l.startswith('y2mate'): continue
                if l.endswith(('.cpr','.npr')): key,kind=dp,'prj'
                elif l.endswith(AUD): key,kind=(os.path.dirname(dp) if os.path.basename(dp)=='Mixdown' else dp),'mix'
                elif l.endswith(MID): key,kind=dp,'mid'
                else: continue
                try: songs[key][kind].append((os.stat(p).st_mtime,f,p))
                except OSError: pass
    rows=sorted(((max(x[0] for x in v['prj']+v['mix']+v['mid']),k,v) for k,v in songs.items() if v['prj'] or v['mix']),reverse=True)
    np=sum(len(v['prj']) for _,_,v in rows); nm=sum(len(v['mix']) for _,_,v in rows)
    summary.append(f"- **[[#{label}]]**: 曲フォルダ {len(rows)}件・プロジェクト {np}件・音源 {nm}件")
    link=lambda p: "file://"+urllib.parse.quote(real+p[len(root):])
    short=lambda p: ((os.path.relpath(p,root)+"/").replace('./','（直下）',1) if os.path.relpath(p,root)=='.' else (os.path.relpath(p,root)+"/")).replace('_移行データ/∕Users∕yoshiakinagumo∕Desktop/','Desktop(M5)/').replace('!!!!!!ONEDRIVER/！ＤＴＭ/','ＤＴＭ/').rstrip('/') or "（直下）"
    def title(k,v):
        if v['prj']: return os.path.splitext(max(v['prj'])[1])[0]
        return os.path.basename(k) or label
    body.append(f"\n## {label}\n")
    if cloud: body.append("> クラウドの中身。Macに未ダウンロードのファイルは、リンクを押すとダウンロードしてから開く。音源の長さは測っていない（測るとダウンロードが走るため）。\n")
    body.append("|最終更新|曲（最新プロジェクト名）|場所|プロジェクト|書き出し|パラ|\n|---|---|---|---:|---:|---:|")
    detail=[]
    for t,k,v in rows:
        full=[m for m in v['mix'] if not STEM.search(m[1])]; stems=[m for m in v['mix'] if STEM.search(m[1])]
        ti=title(k,v)
        body.append(f"|{d(t)}|{ti}|[{short(k)}]({link(k)})|{len(v['prj'])}|{len(full)}|{len(stems)}|")
        detail.append(f"### {ti}\n[{short(k)}]({link(k)})\n")
        if full:
            detail.append("**書き出し音源**")
            fs=sorted(full,reverse=True)
            for m in fs[:15]:
                detail.append(f"- {d(m[0])} [{m[1]}]({link(m[2])}) {'' if cloud else dur(m[2])}")
            if len(fs)>15: detail.append(f"- ほか {len(fs)-15}本 → 上のフォルダを開く")
        if stems:
            detail.append(f"**パラ書き出し** {len(stems)}本 {d(min(stems)[0])}〜{d(max(stems)[0])}")
        if v['prj']:
            detail.append("**プロジェクト**（新しい順）")
            for c in sorted(v['prj'],reverse=True)[:15]:
                detail.append(f"- {d(c[0])} [{c[1]}]({link(c[2])})")
            if len(v['prj'])>15: detail.append(f"- ほか {len(v['prj'])-15}件")
        detail.append("")
    body.append(f"\n### ▼ {label} の曲ごとの中身\n")
    body+=[x.replace("### ","#### ",1) if x.startswith("### ") else x for x in detail]
now=datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
out.append(f"---\n種別: 音楽制作環境 / 作品台帳\n更新: {now}\n---\n\n# 🎵 作品台帳\n")
out.append(f"> [!info] 読み方\n> 自作曲がどこにあるかを、場所ごと・曲（保存フォルダ）ごとにまとめた一覧。表は更新日の新しい順、曲名は最新のCubase／Logicプロジェクト名。**「場所」のリンクを押すとFinderでそのフォルダが開く**。「パラ」はCubaseのトラック別書き出し。\n> 生成: {now}（このMacから見えた分）／ 作り直し: ターミナルで `python3 ~/Documents/\"Obsidian Vault\"/資料/音楽/作品台帳スキャン.py`\n")
out.append("## 場所ごとの件数\n"+"\n".join(summary)+"\n\n対象外にしたもの: OneDriveの市販CD音源（MP3_1・ビートルズマイナス・y2mate）・放送大学・本・音源ソフトのサンプル・AUてんこ盛り、iCloudのプラグイン類フォルダ、各プロジェクトの `Audio` 素材フォルダ。\n")
out+=body
V=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
open(os.path.join(V,"🎵 作品台帳.md"),'w').write("\n".join(out))
print("\n".join(summary))
