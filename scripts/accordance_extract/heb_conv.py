exec(open('heb.py').read())
def ycl3(bs):
    pre,cl=ycl(bs)
    if cl and pre: cl[0][1]=pre+cl[0][1]
    for k in range(len(cl)-1):
        ch,mk=cl[k]
        if cl[k+1][0]=='w' and mk.endswith(b'\xbf')==False and b'\xbf' in mk:
            pass
        if cl[k+1][0]=='w' and b'\xbf' in mk:
            j=mk.rindex(b'\xbf')
            cl[k][1]=mk[:j]+mk[j+1:]; cl[k+1][1]=b'\xbf'+cl[k+1][1]
    return cl
BASE=dict(HLET); BASE['c']='שׂ'; BASE['v']='שׁ'
def learn(PAIRS):
    cm=defaultdict(Counter); single=defaultdict(Counter)
    for y,u in PAIRS:
        yc=ycl3(y); up,uc=ucl(u)
        if up or len(yc)!=len(uc): continue
        for (yl,ym),(ul,um) in zip(yc,uc):
            um=''.join(sorted(um.replace('ׁ','').replace('ׂ','')))
            cm[(yl if yl in 'w' else '',ym)][um]+=1
            if len(ym)==1: single[ym[0]][um]+=1
    CM={k:c.most_common(1)[0][0] for k,c in cm.items()}
    BM={k:c.most_common(1)[0][0] for k,c in single.items()}
    return CM,BM,cm
def hconv(bs,CM,BM,miss=None):
    out=''
    for let,mk in ycl3(bs):
        key=(let if let=='w' else '',mk)
        if key in CM: m=CM[key]
        elif ('',mk) in CM: m=CM[('',mk)]
        else:
            m=''
            for x in mk:
                if x in BM: m+=BM[x]
                elif miss is not None: miss[x]+=1
        out+=BASE[let]+m
    out=ud.normalize('NFC',out)
    out=out.replace('\u0597\u059d','\u059d\u0597')
    if out.count('\u0599')>=2:
        k=out.index('\u0599'); out=out[:k]+'\u05a8'+out[k+1:]
    return out
