exec(open('learn_gr.py').read().split("stats=defaultdict")[0])
from greek import to_uni
import os
PUN={-104:'.',-105:',',-106:'·',-107:';',-111:';',-113:'·',-117:',',-112:'—'}
OPEN={-109:'[',-114:'⟦',-118:'('}
CLOSE={-110:']',-115:'⟧',-119:')'}
def render(i):
    ts=TOK[VS[i]:VS[i+1]]; out=''; k=0; pend=''
    while k<len(ts):
        t=ts[k]
        if t==0xffffffff: k+=1; t=ts[k]; k+=1; continue  # skip first of duplicate pair
        if t<0x80000000:
            wd=to_uni(w[t-1])
            out+=(' ' if out and not out.endswith(('[','⟦','(')) else '')+wd
        else:
            p=t-2**32
            if p in PUN:
                out+= (' — ' if p==-112 else PUN[p])
            elif p in OPEN: out+=(' ' if out else '')+OPEN[p]
            elif p in CLOSE: out+=CLOSE[p]
        k+=1
    out=re.sub(r' +',' ',out).replace('— ','— ').strip()
    out=out.replace('[ ','[').replace('( ','(').replace('⟦ ','⟦')
    return out
JP=["マタイの福音書","マルコの福音書","ルカの福音書","ヨハネの福音書","使徒の働き","ローマ人への手紙","コリント人への手紙第一","コリント人への手紙第二","ガラテヤ人への手紙","エペソ人への手紙","ピリピ人への手紙","コロサイ人への手紙","テサロニケ人への手紙第一","テサロニケ人への手紙第二","テモテへの手紙第一","テモテへの手紙第二","テトスへの手紙","ピレモンへの手紙","ヘブル人への手紙","ヤコブの手紙","ペテロの手紙第一","ペテロの手紙第二","ヨハネの手紙第一","ヨハネの手紙第二","ヨハネの手紙第三","ユダの手紙","ヨハネの黙示録"]
EN=["Matthew","Mark","Luke","John","Acts","Romans","1 Corinthians","2 Corinthians","Galatians","Ephesians","Philippians","Colossians","1 Thessalonians","2 Thessalonians","1 Timothy","2 Timothy","Titus","Philemon","Hebrews","James","1 Peter","2 Peter","1 John","2 John","3 John","Jude","Revelation"]
COPY="Novum Testamentum Graece, Nestle-Aland 28th Revised Edition. Copyright © 2012 Deutsche Bibelgesellschaft, Stuttgart. Used by permission. (Accordance GNT28-T, Version 3.7)"
OUT='out/聖書（ギリシャ語NA28）'; os.makedirs(OUT,exist_ok=True)
idx=["# ギリシャ語新約 NA28（AI内蔵）","","> "+COPY,
"> Accordanceモジュール GNT28-T から抽出（Accordance独自のギリシャ語フォント符号をUnicodeに変換）。本文は改変不可。個人利用のみ・再配布しない。",
"> 各書の冒頭の書名（inscriptio, 例 ΚΑΤΑ ΜΑΘΘΑΙΟΝ）は `0` と `^1-0` で置く。NA28が本文に持たない節（例 Matthew 17:21, Mark 7:16, Romans 16:24）は欠番。節番号はNA28の番号（2コリント13章は13節まで、黙示録12:18あり）。",
"> 本文批評の記号（⸀⸂⸃など）と欄外の異読はモジュールに入っていないため無い。[ ] はNA28の角括弧、⟦ ⟧ は二重角括弧（Mark 16:9–20, John 7:53–8:11 など）。",""]
total=0
by=defaultdict(list)
for b,c,v,i in slots: by[b].append((c,v,i))
for b in range(27):
    name=f"NA28 {JP[b]}"
    L=["---","聖書: NA28（ギリシャ語）",f"書: {JP[b]}",f"英名: {EN[b]}",f"著作権: {COPY}","---","",f"# {EN[b]}（{JP[b]}）NA28",""]
    cur=None; items=by[b]
    # 2 Corinthians 13: NA28 native numbering (sequential)
    if EN[b]=='2 Corinthians':
        n13=[x for x in items if x[0]==13]
        items=[x for x in items if x[0]!=13]+[(13,k+1,x[2]) for k,x in enumerate(n13)]
    for c,v,i in items:
        if c!=cur: L+=[f"## {c}章",""]; cur=c
        L+=[f"{v}　{render(i)} ^{c}-{v}",""]; total+=1
    open(f"{OUT}/{name}.md","w").write("\n".join(L))
    idx.append(f"- [[{name}]]（{EN[b]}）")
open(f"{OUT}/_NA28索引.md","w").write("\n".join(idx)+"\n")
print('verses',total)
