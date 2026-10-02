import sys,re,struct,os
EXTS=('wav','aif','aiff','mp3','flac','ogg','m4a','wma','rex','rx2','caf','w64')
END=re.compile(rb'\.(?:'+b'|'.join(e.encode() for e in EXTS)+rb')\x00',re.I)
DEND=re.compile(rb'[/\\]\x00')
import unicodedata
def dec(b):
    return unicodedata.normalize('NFC',_dec(b))
def _dec(b):
    for e in ('utf-8','cp932','latin-1'):
        try: return b.decode(e)
        except: pass
def lp(d,e,maxlen=600):
    # e = index of NUL; find s with BE uint32 at s-4 == e-s+1
    for s in range(e-1,max(4,e-maxlen),-1):
        if s-4>=0 and d[s-4:s-2]==b'\x00\x00' and struct.unpack('>I',d[s-4:s])[0] in (e-s+1,e-s+4): return s
    return None
def refs(path):
    d=open(path,'rb').read(); ev=[]
    for m in END.finditer(d):
        e=m.end()-1; s=lp(d,e)
        if s is not None: ev.append((s,'F',dec(d[s:e])))
    for m in DEND.finditer(d):
        e=m.end()-1; s=lp(d,e)
        if s is not None:
            t=dec(d[s:e])
            if t and (t.startswith('/') or re.match(r'[A-Za-z]:\\',t)): ev.append((s,'D',t))
    ev.sort(); res=[]; last=None
    for i,k,t in ev:
        if k=='F': last=(i,t)
        elif last and i-last[0]<300: res.append((t,last[1])); last=None
    return res
if __name__=='__main__':
    from collections import Counter
    for p in sys.argv[1:]:
        r=refs(p); u=sorted(set(r))
        print('==',p,'refs',len(r),'unique',len(u))
        for x in u[:5]: print('  ',x)
        print('  dirs:',Counter(d for d,_ in u).most_common(8))
