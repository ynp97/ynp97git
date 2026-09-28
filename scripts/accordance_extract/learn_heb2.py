exec(open('heb.py').read())
OS={}
for b,bk in enumerate(HB):
    for k,v in oshb_verses(bk).items(): OS[(b,)+k]=v
import difflib
def ysk2(y): return ''.join(HLET[chr(x)] for x in y if chr(x) in HLET).translate(str.maketrans('ךםןףץ','כמנפצ'))
def usk(u): return ''.join(ch for ch in ud.normalize('NFD',u) if 'א'<=ch<='ת').translate(str.maketrans('ךםןףץ','כמנפצ'))
def ywords(bs): return [x for x in re.split(rb'[ _:\[\]()]+',bs) if x]
PAIRS=[]
for b,c,v,i in SLOTS:
    if (b,c,v) not in OS: continue
    uw=OS[(b,c,v)][0]; yw=ywords(vblob(i))
    sm=difflib.SequenceMatcher(None,[ysk2(x) for x in yw],[usk(x) for x in uw],autojunk=False)
    for tag,a1,a2,b1,b2 in sm.get_opcodes():
        if tag=='equal':
            for k in range(a2-a1): PAIRS.append((yw[a1+k],uw[b1+k]))
pickle.dump(PAIRS,open('heb_pairs.pkl','wb'))
print(len(PAIRS))
