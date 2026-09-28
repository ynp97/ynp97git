import sys; sys.path.insert(0,'.')
from greek import *
from acc import *
import difflib, glob
w=pickle.load(open('gnt_words.pkl','rb'))[:19034]
d=open('GNT28-T','rb').read()
VT=381851; NV=7968; TX=447183-24; NT=166678
VS=list(struct.unpack('<%dI'%NV,d[VT:VT+4*NV]))+[NT]
TOK=struct.unpack('<%dI'%NT,d[TX:TX+4*NT])
m=Mod('GNT28-T',27,(28,44),'little'); tabs=find_tables(d,446000,'<')
SBL=['Matt','Mark','Luke','John','Acts','Rom','1Cor','2Cor','Gal','Eph','Phil','Col','1Thess','2Thess','1Tim','2Tim','Titus','Phlm','Heb','Jas','1Pet','2Pet','1John','2John','3John','Jude','Rev']
def vwords(i):
    ts=TOK[VS[i]:VS[i+1]]; out=[]; k=0
    while k<len(ts):
        t=ts[k]
        if t==0xffffffff: k+=2; continue
        if t<0x80000000: out.append(w[t-1])
        k+=1
    return out
# build slot -> (book, ch, v)
slots=[]
for b,en in enumerate(BOOKS[39:]):
    L=labels_generic(m,b,en,446000,tabs,title_first_chapter=True)
    for ci,(labs,s) in enumerate(L):
        for j,v in enumerate(labs): slots.append((b,ci+1,v,s-1+j))
sbl={}
for b,ab in enumerate(SBL):
    for line in open(f'sbl/{ab}.txt',encoding='utf-8'):
        mm=re.match(r'^\S+ (\d+):(\d+)\t(.*)',line)
        if mm: sbl[(b,int(mm.group(1)),int(mm.group(2)))]=mm.group(3)
stats=defaultdict(Counter)   # (cluster bytes, is_cap) -> Counter(marks)
pairs=0; mism=0
for b,c,v,i in slots:
    u=sbl.get((b,c,v))
    if not u: continue
    hw=vwords(i)
    uw=[x for x in re.findall(r'[\ẁ-ͯἀ-῿’]+',u) if skel_u(x)]
    hs=[skel_h(x) for x in hw]; us=[skel_u(x) for x in uw]
    sm=difflib.SequenceMatcher(None,hs,us,autojunk=False)
    for tag,a1,a2,b1,b2 in sm.get_opcodes():
        if tag!='equal': continue
        for k in range(a2-a1):
            H=hw[a1+k]; U=uw[b1+k]
            cl=clusters(H); um=umarks(U)
            cl=[x for x in cl if x[1]]
            if len(cl)!=len(um): mism+=1; continue
            pairs+=1
            for (pre,let,post),(ul,mk) in zip(cl,um):
                key=(pre+post)
                stats[key][''.join(sorted(ud.normalize('NFD',mk)))]+=1
print('pairs',pairs,'mism',mism)
MAP={}
amb=[]
for k,c in stats.items():
    top,n=c.most_common(1)[0]; tot=sum(c.values())
    MAP[k]=top
    if n/tot<0.97 and tot>3: amb.append((k,c.most_common(3),tot))
print(len(MAP)); 
for a in amb[:30]: print(a[0].decode('latin1'),[(ud.name(x[0][0]) if x[0] else '',x[1]) for x in a[1]],a[2])
pickle.dump(MAP,open('gr_map.pkl','wb'))
