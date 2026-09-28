import pickle,struct
w=pickle.load(open('esv_words.pkl','rb'))
w[-1]='Zuzim'
d=open('ESVS','rb').read()
TX=606582; VT=336702; NVS=31202
TOTAL=967023
VS=list(struct.unpack('>%dI'%NVS,d[VT:VT+4*NVS]))+[TOTAL]
TOK=struct.unpack('>%dH'%TOTAL,d[TX:TX+2*TOTAL])
def vtok(i): return TOK[VS[i]:VS[i+1]]
def show(ts): return ' '.join(w[t-1] if 1<=t<=len(w) else hex(t) for t in ts)
PB=d.find(b', . @ ',46000)
_k=PB-4; _v=[]
while True:
    _x=struct.unpack('>I',d[_k:_k+4])[0]
    if _v and _x>=_v[-1]: break
    _v.append(_x); _k-=4
_v=_v[::-1]
PUN=[d[PB+_v[i]-1:PB+_v[i+1]-1].decode('mac_roman') for i in range(len(_v)-1)]
PBASE=0x7ef5
import re as _re
def render(ts):
    out=[]; skip=False; i=0; ts=list(ts)
    while i<len(ts):
        t=ts[i]
        if t==0x7ffe: i+=1; continue
        if t==0x7fff: i+=1; ts.pop(i); continue   # next token duplicated -> drop one copy
        if 1<=t<=len(w):
            if out and not out[-1].endswith((' ','\t','“','‘','(','[','-','—')): out.append(' ')
            out.append(w[t-1])
        else:
            p=PUN[t-PBASE]
            out.append(p)
        i+=1
    s=''.join(out)
    s=s.replace('@','')
    s=_re.sub(r'\s*—\s*','—',s)
    s=_re.sub(r'[\t\xa0 ]+',' ',s).strip()
    return s
