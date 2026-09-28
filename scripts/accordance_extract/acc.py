import struct,json,re
std=json.load(open('std_versification.json')); BOOKS=list(std.keys())
def u16(d,o,e='big'): return int.from_bytes(d[o:o+2],e)
class Mod:
    def __init__(s,f,nbooks,firstbook_chapters,e='big'):
        d=s.d=open(f,'rb').read(); s.e=e
        U=lambda d,o: u16(d,o,e)
        s.C=d.find(struct.pack(('>' if e=='big' else '<')+'2H',*firstbook_chapters))
        s.nb=nbooks
        s.cum=[U(d,s.C+2*i) for i in range(nbooks)]
        s.nch=s.cum[-1]
        # book starts follow
        s.bstart=[U(d,s.C+2*nbooks+2*i)&0x7fff for i in range(nbooks)]
        p=s.C+4*nbooks
        assert sorted([U(d,p),U(d,p+2)])==[0,s.nch],(U(d,p),U(d,p+2))
        s.masked=[U(d,p+4+2*i)&0x7fff for i in range(s.nch)]
    def cstart(s,c): return 1 if c==0 else s.masked[c-1]
    def book_chapters(s,b):
        c0=s.cum[b-1] if b>0 else 0
        return [(s.cstart(c0+k), s.cstart(c0+k+1)-s.cstart(c0+k)) for k in range(s.cum[b]-c0)]

LITTLE=False
def find_map_table(d, nmod, nstd, lim, chs=None, stdch=None):
    E='<' if LITTLE else '>'
    pat=struct.pack(E+'3H',1,2,3)
    for m in re.finditer(re.escape(pat), d[:lim]):
        o=m.start()
        if o+2*nmod>len(d): continue
        a=struct.unpack(E+'%dH'%nmod, d[o:o+2*nmod])
        if a[-1]==nstd and all(a[i]>a[i-1] for i in range(1,nmod)):
            if chs is None: return list(a)
            cv=[]
            for c,n in enumerate(stdch,1): cv+=[c]*n
            k=0; ok=True
            for ci,(s,n) in enumerate(chs):
                if any(cv[a[k+j]-1]!=ci+1 for j in range(n)): ok=False;break
                k+=n
            if ok: return list(a)
    return None

def verse_labels(mod, b, en, lim, title_ok=True):
    """return list per chapter of verse labels for module slots of book b"""
    chs=mod.book_chapters(b)
    stdch=[int(std[en][str(c)]) for c in range(1,len(std[en])+1)]
    nmod=sum(n for s,n in chs); nstd=sum(stdch)
    out=[]
    if nmod==nstd and all(n==stdch[i] for i,(s,n) in enumerate(chs)):
        return [(list(range(1,n+1)),s) for s,n in chs]
    tab=find_map_table(mod.d,nmod,nstd,lim,chs,stdch) if nmod<nstd else None
    if tab:
        # std book index -> (ch,v)
        cv=[]
        for c,n in enumerate(stdch,1):
            cv+= [(c,v) for v in range(1,n+1)]
        k=0
        for ci,(s,n) in enumerate(chs):
            labs=[]
            for j in range(n):
                c,v=cv[tab[k]-1]; k+=1
                assert c==ci+1,(en,ci+1,c,v)
                labs.append(v)
            out.append((labs,s))
        return out
    # per-chapter: extra leading slot = title (0)
    for ci,(s,n) in enumerate(chs):
        sn=stdch[ci]
        if n==sn: out.append((list(range(1,n+1)),s))
        elif n==sn+1 and title_ok: out.append(([0]+list(range(1,sn+1)),s))
        else: raise Exception(f'unresolved {en} {ci+1}: module {n} std {sn}')
    return out

def find_tables(d, lim, E):
    """all u16 increasing runs starting with 1,2,3 (optionally preceded by one title value)"""
    out=[]
    pat=struct.pack(E+'3H',1,2,3)
    for m in re.finditer(re.escape(pat), d[:lim]):
        o=m.start(); j=o+2; prev=1
        while j+2<=lim:
            v=struct.unpack(E+'H',d[j:j+2])[0]
            if v<=prev or v-prev>4: break
            prev=v; j+=2
        n=(j-o)//2
        if n>=10: out.append((o,[struct.unpack(E+'H',d[o+2*k:o+2*k+2])[0] for k in range(n)]))
    return out

def labels_generic(mod, b, en, lim, tables, title_first_chapter=False, title_psalms=False):
    chs=mod.book_chapters(b)
    stdch=[int(std[en][str(c)]) for c in range(1,len(std[en])+1)]
    res=[]; need=[]
    for ci,(s,n) in enumerate(chs):
        sn=stdch[ci]; lead=[]
        if title_first_chapter and ci==0: lead=[0]; n2=n-1
        elif title_psalms and n==sn+1: lead=[0]; n2=n-1
        else: n2=n
        res.append([lead, n2, sn, s])
        if n2<sn: need.append(ci)
    if need:
        # std book-index -> (ch,v)
        cv=[]
        for c,n in enumerate(stdch,1): cv+=[(c,v) for v in range(1,n+1)]
        nstd=len(cv)
        body=sum(r[1] for r in res)
        cand=None
        for o,a in tables:
            if len(a)<body: continue
            a=a[:body]
            if a[-1]>nstd: continue
            k=0; ok=True
            for ci,r in enumerate(res):
                seg=a[k:k+r[1]]; k+=r[1]
                if any(x>nstd or cv[x-1][0]!=ci+1 for x in seg): ok=False; break
            if ok and a[-1]==nstd or (ok and a[-1]<=nstd and en=='Revelation'): cand=a; break
        if cand is None: raise Exception('no table for '+en)
        k=0
        for ci,r in enumerate(res):
            seg=cand[k:k+r[1]]; k+=r[1]
            r.append([cv[x-1][1] for x in seg])
    out=[]
    for ci,r in enumerate(res):
        lead,n2,sn,s=r[:4]
        if len(r)==5 and n2<sn: labs=r[4]
        else: labs=list(range(1,n2+1))
        out.append((lead+labs,s))
    return out
