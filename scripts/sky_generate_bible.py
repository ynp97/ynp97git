import json, os, re
data=open('SKY2017.atext/SKY2017','rb').read()
def u16(o): return int.from_bytes(data[o:o+2],'big')
VT=0x88dc82; TEXT0=0x8ac40e; NV=31202
def voff(i): return (int.from_bytes(data[VT+4*i:VT+4*i+4],'big')>>8)
def gtext(g):
    if g==1: return data[TEXT0:TEXT0+voff(0)].decode('utf-8','replace')
    a=voff(g-2); b=voff(g-1) if g-1<NV else len(data)-TEXT0
    return data[TEXT0+a:TEXT0+b].decode('utf-8','replace')
def clean(t):
    return re.sub(r'[ \t　]+',' ', t.replace('\r',' ').replace('\n',' ')).strip()
masked=[u16(0x8d8e+2*i)&0x7fff for i in range(1189)]
def cstart(c): return 1 if c==0 else masked[c-1]   # c=0-based global chapter idx -> global 1-based verse
cumch=[u16(0x8c82+2*i) for i in range(66)]
std=json.load(open('std_versification.json')); books=list(std.keys())
JP=["創世記","出エジプト記","レビ記","民数記","申命記","ヨシュア記","士師記","ルツ記","サムエル記第一","サムエル記第二","列王記第一","列王記第二","歴代誌第一","歴代誌第二","エズラ記","ネヘミヤ記","エステル記","ヨブ記","詩篇","箴言","伝道者の書","雅歌","イザヤ書","エレミヤ書","哀歌","エゼキエル書","ダニエル書","ホセア書","ヨエル書","アモス書","オバデヤ書","ヨナ書","ミカ書","ナホム書","ハバクク書","ゼパニヤ書","ハガイ書","ゼカリヤ書","マラキ書","マタイの福音書","マルコの福音書","ルカの福音書","ヨハネの福音書","使徒の働き","ローマ人への手紙","コリント人への手紙第一","コリント人への手紙第二","ガラテヤ人への手紙","エペソ人への手紙","ピリピ人への手紙","コロサイ人への手紙","テサロニケ人への手紙第一","テサロニケ人への手紙第二","テモテへの手紙第一","テモテへの手紙第二","テトスへの手紙","ピレモンへの手紙","ヘブル人への手紙","ヤコブの手紙","ペテロの手紙第一","ペテロの手紙第二","ヨハネの手紙第一","ヨハネの手紙第二","ヨハネの手紙第三","ユダの手紙","ヨハネの黙示録"]
OMIT={
 'Nehemiah':{(7,68)},
 'Mark':{(7,16),(9,44),(9,46),(11,26),(15,28)},
 'Luke':{(1,2),(1,25),(17,36),(23,17)},
 'John':{(5,4)},
 'Acts':{(8,37),(15,34),(19,41),(24,7),(28,29)},
 'Romans':{(2,20),(16,24)},
 '2 Corinthians':{(13,13)},
}
OUTDIR="/sessions/brave-laughing-tesla/mnt/Obsidian Vault/聖書（新改訳2017）"
os.makedirs(OUTDIR, exist_ok=True)
COPY="聖書 新改訳2017 ©2017 新日本聖書刊行会（許諾番号 3-1-274 / Version 1.3）"
total=0
index_lines=["# 聖書 新改訳2017（AI内蔵）","", "> "+COPY, "> Accordanceモジュールから抽出。本文は改変不可。", ""]
for bi,en in enumerate(books):
    jp=JP[bi]; nchap=len(std[en])
    omit=OMIT.get(en,set())
    # build display numbers per chapter
    lines=[f"---","聖書: 新改訳2017",f"書: {jp}",f"英名: {en}",f"著作権: {COPY}","---","",f"# {jp}",""]
    gc0 = cumch[bi-1] if bi>0 else 0   # global chapter index of this book's ch1
    for ch in range(1, nchap+1):
        ci = gc0 + (ch-1)
        gstart=cstart(ci); gend=cstart(ci+1)
        nblk=gend-gstart
        # display numbers for this chapter
        stdn=int(std[en][str(ch)])
        nums=[v for v in range(1,stdn+1) if (ch,v) not in omit]
        # for Psalm/Rev/others where module has >=std, nums may be shorter than nblk -> extend sequentially
        if len(nums)<nblk:
            nums = list(range(1,nblk+1))
        elif len(nums)>nblk:
            nums = nums[:nblk]
        lines.append(f"## {ch}章"); lines.append("")
        for k in range(nblk):
            v=nums[k]; t=clean(gtext(gstart+k))
            lines.append(f"{v}　{t} ^{ch}-{v}")
            lines.append("")
            total+=1
    open(os.path.join(OUTDIR,f"{jp}.md"),"w").write("\n".join(lines))
    index_lines.append(f"- [[{jp}]]（{nchap}章）")
open(os.path.join(OUTDIR,"_聖書索引.md"),"w").write("\n".join(index_lines))
print("total verses written:", total, "expected 31202", total==31202)
print("files:", len(os.listdir(OUTDIR)))
