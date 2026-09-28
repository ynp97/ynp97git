exec(open('heb_conv.py').read())
CM,BM=pickle.load(open('heb_cm.pkl','rb'))
import os
HBJP={'Gen':'創世記','Exod':'出エジプト記','Lev':'レビ記','Num':'民数記','Deut':'申命記','Josh':'ヨシュア記','Judg':'士師記','Ruth':'ルツ記','1Sam':'サムエル記第一','2Sam':'サムエル記第二','1Kgs':'列王記第一','2Kgs':'列王記第二','1Chr':'歴代誌第一','2Chr':'歴代誌第二','Ezra':'エズラ記','Neh':'ネヘミヤ記','Esth':'エステル記','Job':'ヨブ記','Ps':'詩篇','Prov':'箴言','Eccl':'伝道者の書','Song':'雅歌','Isa':'イザヤ書','Jer':'エレミヤ書','Lam':'哀歌','Ezek':'エゼキエル書','Dan':'ダニエル書','Hos':'ホセア書','Joel':'ヨエル書','Amos':'アモス書','Obad':'オバデヤ書','Jonah':'ヨナ書','Mic':'ミカ書','Nah':'ナホム書','Hab':'ハバクク書','Zeph':'ゼパニヤ書','Hag':'ハガイ書','Zech':'ゼカリヤ書','Mal':'マラキ書'}
ENG=['Gen','Exod','Lev','Num','Deut','Josh','Judg','Ruth','1Sam','2Sam','1Kgs','2Kgs','1Chr','2Chr','Ezra','Neh','Esth','Job','Ps','Prov','Eccl','Song','Isa','Jer','Lam','Ezek','Dan','Hos','Joel','Amos','Obad','Jonah','Mic','Nah','Hab','Zeph','Hag','Zech','Mal']
ENNAME=dict(zip(ENG,["Genesis","Exodus","Leviticus","Numbers","Deuteronomy","Joshua","Judges","Ruth","1 Samuel","2 Samuel","1 Kings","2 Kings","1 Chronicles","2 Chronicles","Ezra","Nehemiah","Esther","Job","Psalms","Proverbs","Ecclesiastes","Song of Songs","Isaiah","Jeremiah","Lamentations","Ezekiel","Daniel","Hosea","Joel","Amos","Obadiah","Jonah","Micah","Nahum","Habakkuk","Zephaniah","Haggai","Zechariah","Malachi"]))
def render(bl):
    toks=re.split(rb'([ _:\[\]()])',bl)
    out=[]; inpar=False
    for t in toks:
        if t==b'': continue
        if t==b' ': out.append(' ')
        elif t==b'_': out.append('־')
        elif t==b':': out.append('׃')
        elif t==b']': out.append('[')
        elif t==b'[': out.append(']')
        elif t==b')': inpar=True
        elif t==b'(': inpar=False
        elif inpar: pass
        elif t in (b'p',b's'): out.append('פ' if t==b'p' else 'ס')
        else:
            pas=t.endswith(b'\xd1')
            if pas: t=t.rstrip(b'\xd1')
            out.append(hconv(t,CM,BM)+(' ׀' if pas else ''))
    s=''.join(out)
    s=re.sub(r' +',' ',s).replace('[ ','[').replace(' ]',']').replace('][','').strip()
    return s
COPY="Hebrew Masoretic Text of the Leningrad Codex with Westminster Hebrew Morphology (Accordance HMT-W4, Version 3.4). Groves-Wheeler Westminster Hebrew Morphology v4.22, © 1991–2020 The J. Alan Groves Center for Advanced Biblical Research."
OUT='out/聖書（ヘブル語HMT）'; os.makedirs(OUT,exist_ok=True)
by=defaultdict(list)
for b,c,v,i in SLOTS: by[HB[b]].append((c,v,i))
idx=["# ヘブル語旧約 HMT（レニングラード写本・AI内蔵）","","> "+COPY,
"> Accordanceモジュール HMT-W4 から抽出（Accordance独自のヘブル語フォント符号をUnicodeに変換。母音記号・アクセント記号つき）。本文は改変不可。個人利用のみ・再配布しない。",
"> **章節はヘブル語聖書の番号**（詩篇の表題は1節、マラキ3:19–24＝英語4:1–6、ヨエル3–4章＝英語2:28–3:21 など）。英語・日本語聖書と番号がずれる箇所がある。",
"> ケティーブ／ケレーは「ケティーブ [ケレー]」の形。ケティーブにはケレーの母音が付いている（レニングラード写本の慣例）。ケレーだけの語は [ ] のみ。׀ はパセク、行末の פ／ס は段落記号（ペトゥハー／セトゥマー）。",""]
total=0
for bk in ENG:
    name=f"HMT {HBJP[bk]}"
    L=["---","聖書: HMT（ヘブル語・レニングラード写本）",f"書: {HBJP[bk]}",f"英名: {ENNAME[bk]}",f"著作権: {COPY}","---","",f"# {ENNAME[bk]}（{HBJP[bk]}）HMT",""]
    cur=None
    for c,v,i in by[bk]:
        if c!=cur: L+=[f"## {c}章",""]; cur=c
        L+=[f"{v}　{render(vblob(i))} ^{c}-{v}",""]; total+=1
    open(f"{OUT}/{name}.md","w").write("\n".join(L))
    idx.append(f"- [[{name}]]（{ENNAME[bk]}, {cur}章）")
open(f"{OUT}/_HMT索引.md","w").write("\n".join(idx)+"\n")
print('verses',total)
