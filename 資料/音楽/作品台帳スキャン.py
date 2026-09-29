import re, os, subprocess, datetime, urllib.parse, collections, json
ROOT="/Volumes/BENJAMIN" if os.path.isdir("/Volumes/BENJAMIN") else os.path.expanduser("~/mnt/BENJAMIN")
REAL="/Volumes/BENJAMIN"
AUD=('.wav','.mp3','.aif','.aiff','.m4a','.flac')
MID=('.mid','.midi')
skip_top={'Obsidian Vault','DCIM','MISC','OP42','OP43','OP４５','op44','op46','op47'}
songs=collections.defaultdict(lambda:{'cpr':[],'mix':[],'mid':[]})
for dp,dn,fn in os.walk(ROOT):
    rel=os.path.relpath(dp,ROOT)
    top=rel.split(os.sep)[0]
    if top in skip_top: dn[:]=[]; continue
    dn[:]=[d for d in dn if d not in('Audio','Edits','Images','FREEVSTS','06_書籍・マンガ','Final Cut Original Media') and not d.startswith('.')]
    for f in fn:
        p=os.path.join(dp,f); l=f.lower()
        if l.endswith('.cpr'): key=dp; kind='cpr'
        elif l.endswith(AUD+MID):
            key=os.path.dirname(dp) if os.path.basename(dp)=='Mixdown' else dp
            kind='mid' if l.endswith(MID) else 'mix'
        else: continue
        st=os.stat(p)
        songs[key][kind].append((st.st_mtime,f,p,st.st_size))
def dur(p):
    try:
        o=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',p],capture_output=True,text=True,timeout=20).stdout.strip()
        s=float(o); return f"{int(s//60)}:{int(s%60):02d}"
    except: return "?"
def d(t): return datetime.datetime.fromtimestamp(t).strftime('%Y-%m-%d')
def link(p):
    real=REAL+p[len(ROOT):]
    return "file://"+urllib.parse.quote(real)
def short(p):
    s=p[len(ROOT)+1:]
    return s.replace('_移行データ/∕Users∕yoshiakinagumo∕Desktop/','Desktop(M5)/')
rows=[]
for k,v in songs.items():
    latest=max([x[0] for x in v['cpr']+v['mix']+v['mid']])
    rows.append((latest,k,v))
rows.sort(reverse=True)
out=[]
tot_c=sum(len(v['cpr']) for _,_,v in rows); tot_m=sum(len(v['mix']) for _,_,v in rows)
out.append("---\n種別: 音楽制作環境 / 作品台帳\n作成日: %s\n対象: 外付けSSD BENJAMIN\n---\n"%datetime.date.today())
out.append("# 🎵 作品台帳（BENJAMIN）\n")
out.append("> [!info] 読み方\n> BENJAMINを走査して、**曲（保存フォルダ）ごと**にCubaseプロジェクトと書き出し音源（Mixdown）をまとめた一覧。更新日の新しい順。曲名は最新CPRのファイル名。「パラ書き出し」はCubaseのトラック別書き出し（`名前 - 0001 - インストゥルメント - …`）で、完成音源とは分けて数だけ出す。リンクはBENJAMINを挿しているMacでクリックすると開く（CPR→Cubase、音源→再生）。\n> 生成: %s ／ 曲フォルダ %d件・CPR %d件・書き出し音源 %d件 ／ 再生成: `python3 資料/音楽/作品台帳スキャン.py`\n"%(datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),len(rows),tot_c,tot_m))
out.append("> [!warning] BENJAMINに無いもの\n> BENJAMINにあるのはM5のデスクトップを8/15に移した分だけ。[[🎛 Cubaseプロジェクト地図]]（7/13時点・441件）のうち **OneDrive 345件・iCloud書類（SongsPro等）8件はここに入っていない**。\n")
out.append("## 一覧（曲名だけ見る）\n\n|最終更新|曲（最新CPR名）|CPR版数|書き出し|パラ書き出し|\n|---|---|---:|---:|---:|")
STEM=re.compile(r' - \d{4} - ')
def title(k,v):
    if v['cpr']: return os.path.splitext(max(v['cpr'])[1])[0]
    return os.path.basename(k)
for t,k,v in rows:
    full=[m for m in v['mix'] if not STEM.search(m[1])]; stems=len(v['mix'])-len(full)
    out.append(f"|{d(t)}|[[#{title(k,v)}]]|{len(v['cpr'])}|{len(full)}|{stems}|")
out.append("\n## 曲ごとの中身\n")
for t,k,v in rows:
    out.append(f"### {title(k,v)}\n`{short(k)}`\n")
    full=[m for m in v['mix'] if not STEM.search(m[1])]; stems=[m for m in v['mix'] if STEM.search(m[1])]
    if full:
        out.append("**書き出し音源**")
        for m in sorted(full,reverse=True):
            out.append(f"- {d(m[0])} [{m[1]}]({link(m[2])}) （{dur(m[2])}）")
    if stems:
        md=os.path.dirname(stems[0][2])
        out.append(f"**パラ書き出し（トラック別）** {len(stems)}本 {d(min(stems)[0])}〜{d(max(stems)[0])} → [フォルダを開く]({link(md)})")
    if v['cpr']:
        out.append("**Cubaseプロジェクト**（新しい順）")
        for c in sorted(v['cpr'],reverse=True):
            out.append(f"- {d(c[0])} [{c[1]}]({link(c[2])}) {c[3]//1024} KB")
    if v['mid']:
        out.append("**MIDI**")
        for c in sorted(v['mid'],reverse=True):
            out.append(f"- {d(c[0])} [{c[1]}]({link(c[2])})")
    out.append("")
VAULT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
open(os.path.join(VAULT,"🎵 作品台帳（BENJAMIN）.md"),'w').write("\n".join(out))
print(len(rows),tot_c,tot_m)
