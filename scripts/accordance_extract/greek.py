import unicodedata as ud, re, struct, pickle
from collections import Counter, defaultdict
LET={c:g for c,g in zip('abgdezhqiklmnxoprstufcyw','αβγδεζηθικλμνξοπρστυφχψω')}
LET.update({c.upper():g.upper() for c,g in LET.items()})
LET['\xa7']='ς'
def is_letter(b): return chr(b) in LET
def clusters(bs):
    """split helena bytes into list of (pre_marks, letter, post_marks)"""
    items=[]; pend=b''
    for b in bs:
        ch=chr(b) if b<128 else bytes([b]).decode('latin1')
        if ch in LET: items.append([pend,ch,b'']); pend=b''
        else:
            if items and not (items and False): items[-1][2]+=bytes([b])
            else: pend+=bytes([b])
    if pend and items: items[-1][2]+=pend
    elif pend: items.append([pend,'',b''])
    return items
def skel_h(bs): return ''.join(LET[c] for c in bs.decode('latin1') if c in LET).lower().replace('ς','σ')
def skel_u(s):
    s=ud.normalize('NFD',s); s=''.join(c for c in s if not ud.combining(c) and c.isalpha())
    return s.lower().replace('ς','σ')
def umarks(s):
    """list of (letter, marks) for unicode word"""
    out=[]
    for c in ud.normalize('NFD',s):
        if ud.combining(c):
            if out: out[-1][1]+=c
        elif c.isalpha(): out.append([c,''])
    return out
GMAP=None
def to_uni(bs):
    global GMAP
    if GMAP is None: GMAP=pickle.load(open('gr_map.pkl','rb'))
    out=''
    for pre,let,post in clusters(bs):
        if not let: raise KeyError(('noletter',bs))
        key=pre+post; tail=''
        if key.endswith(b'\xd5'): key=key[:-1]; tail='’'
        if key.endswith(b'\x87'): key=key[:-1]; tail='ʹ'
        if b' ' in key: key,_,rest=key.partition(b' '); tail=' '+to_uni(rest) if rest else ' '
        mk=GMAP.get(key)
        if mk is None: raise KeyError(key)
        order={'\u0313':0,'\u0314':0,'\u0308':1,'\u0301':2,'\u0300':2,'\u0342':2,'\u0345':3}
        mk=''.join(sorted(mk,key=lambda c:order.get(c,9)))
        out+=LET[let]+mk+tail
    out=ud.normalize('NFC',out)
    return out
