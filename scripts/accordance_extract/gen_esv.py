from acc import *
from esv_lib import *
import os
A=struct.unpack('>%dH'%TOTAL,d[2540632+72532*2+4:2540632+72532*2+4+2*TOTAL])
Lw=w.index('Lord')+1; Lsw=w.index('Lord’s')+1; Gw=w.index('God')+1
YHWH={8504,8486,8505}
def render_v(i):
    ts=list(vtok(i)); tags=list(A[VS[i]:VS[i+1]])
    words=[]
    for k,(t,a) in enumerate(zip(ts,tags)):
        if t in (Lw,Lsw) and a in YHWH: words.append(('LORD' if t==Lw else 'LORD’s'))
        elif t==Gw and (a==8505 or (a==8504 and k>0 and any(ts[j]==Lw for j in range(max(0,k-3),k)))): words.append('GOD')
        else: words.append(None)
    # render with overrides
    out=[]; k=0
    while k<len(ts):
        t=ts[k]
        if t==0x7ffe: k+=1; continue
        if t==0x7fff: k+=2; continue   # skip marker and first duplicate; keep second
        if 1<=t<=len(w):
            if out and not out[-1].endswith((' ','\t','“','‘','(','[','-','—')): out.append(' ')
            out.append(words[k] or w[t-1])
        else: out.append(PUN[t-PBASE])
        k+=1
    s=''.join(out).replace('@','').replace('#','')
    s=re.sub(r'\s*—\s*','—',s); s=re.sub(r'[\t\xa0 ]+',' ',s).strip()
    s=s.replace('[[','⟦').replace(']]','⟧')
    s=re.sub(r'([“‘(\[⟦]) +',r'\1',s); s=re.sub(r' +([’”)\]⟧,.;:!?])',r'\1',s)
    return s
m=Mod('ESVS',66,(50,90))
JP=["創世記","出エジプト記","レビ記","民数記","申命記","ヨシュア記","士師記","ルツ記","サムエル記第一","サムエル記第二","列王記第一","列王記第二","歴代誌第一","歴代誌第二","エズラ記","ネヘミヤ記","エステル記","ヨブ記","詩篇","箴言","伝道者の書","雅歌","イザヤ書","エレミヤ書","哀歌","エゼキエル書","ダニエル書","ホセア書","ヨエル書","アモス書","オバデヤ書","ヨナ書","ミカ書","ナホム書","ハバクク書","ゼパニヤ書","ハガイ書","ゼカリヤ書","マラキ書","マタイの福音書","マルコの福音書","ルカの福音書","ヨハネの福音書","使徒の働き","ローマ人への手紙","コリント人への手紙第一","コリント人への手紙第二","ガラテヤ人への手紙","エペソ人への手紙","ピリピ人への手紙","コロサイ人への手紙","テサロニケ人への手紙第一","テサロニケ人への手紙第二","テモテへの手紙第一","テモテへの手紙第二","テトスへの手紙","ピレモンへの手紙","ヘブル人への手紙","ヤコブの手紙","ペテロの手紙第一","ペテロの手紙第二","ヨハネの手紙第一","ヨハネの手紙第二","ヨハネの手紙第三","ユダの手紙","ヨハネの黙示録"]
EN=["Genesis","Exodus","Leviticus","Numbers","Deuteronomy","Joshua","Judges","Ruth","1 Samuel","2 Samuel","1 Kings","2 Kings","1 Chronicles","2 Chronicles","Ezra","Nehemiah","Esther","Job","Psalms","Proverbs","Ecclesiastes","Song of Solomon","Isaiah","Jeremiah","Lamentations","Ezekiel","Daniel","Hosea","Joel","Amos","Obadiah","Jonah","Micah","Nahum","Habakkuk","Zephaniah","Haggai","Zechariah","Malachi","Matthew","Mark","Luke","John","Acts","Romans","1 Corinthians","2 Corinthians","Galatians","Ephesians","Philippians","Colossians","1 Thessalonians","2 Thessalonians","1 Timothy","2 Timothy","Titus","Philemon","Hebrews","James","1 Peter","2 Peter","1 John","2 John","3 John","Jude","Revelation"]
COPY="The Holy Bible, English Standard Version (ESV), Text Edition 2016. Copyright © 2001, 2006, 2011, 2016 by Crossway Bibles, a division of Good News Publishers. All rights reserved."
OUT='out/聖書（ESV）'; os.makedirs(OUT,exist_ok=True)
idx=["# 聖書 ESV（AI内蔵）","","> "+COPY,"> Accordanceモジュール ESVS（Version 6.5）から抽出。本文は改変不可。個人利用のみ・再配布しない。","> 詩篇の表題は英語聖書の慣例どおり節番号なし（このファイルでは `0` と `^章-0` で置く）。ESVが本文から外して脚注にした節（例 Matthew 17:21, Mark 7:16）は欠番のまま。ESVの二重角括弧（［［ ］］）（Mark 16:9–20, John 7:53–8:11）はObsidianのリンクと衝突するため ⟦ ⟧ で表記。LORD/GOD の小型大文字はStrong番号（H3068/H3069/H3050）から復元、出エジプト3:14の I AM WHO I AM は個別に復元。",""]
total=0
for b,en in enumerate(BOOKS):
    name=f"ESV {JP[b]}"
    L=["---","聖書: ESV",f"書: {JP[b]}",f"英名: {EN[b]}",f"著作権: {COPY}","---","",f"# {EN[b]}（{JP[b]}）",""]
    for ci,(labs,s) in enumerate(verse_labels(m,b,en,336702)):
        L+= [f"## {ci+1}章",""]
        for j,v in enumerate(labs):
            txt=render_v(s-1+j)
            if en=='Exodus' and ci+1==3 and v==14:
                txt=txt.replace('“I am who I am.”','“I AM WHO I AM.”').replace('‘I am has sent','‘I AM has sent')
            L+= [f"{v}　{txt} ^{ci+1}-{v}",""]; total+=1
    open(f"{OUT}/{name}.md","w").write("\n".join(L))
    idx.append(f"- [[{name}]]（{EN[b]}, {len(std[en])}章）")
open(f"{OUT}/_ESV索引.md","w").write("\n".join(idx)+"\n")
print('verses',total)
