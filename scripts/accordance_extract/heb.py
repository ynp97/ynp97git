import re, unicodedata as ud, struct, pickle
from collections import Counter, defaultdict
import xml.etree.ElementTree as ET
NS='{http://www.bibletechnologies.net/2003/OSIS/namespace}'
HB=['Gen','Exod','Lev','Num','Deut','Josh','Judg','1Sam','2Sam','1Kgs','2Kgs','Isa','Jer','Ezek','Hos','Joel','Amos','Obad','Jonah','Mic','Nah','Hab','Zeph','Hag','Zech','Mal','1Chr','2Chr','Ps','Job','Prov','Ruth','Song','Eccl','Lam','Esth','Dan','Ezra','Neh']
def oshb_verses(book):
    t=ET.parse(f'oshb/{book}.xml').getroot()
    out={}
    for v in t.iter(NS+'verse'):
        c,vn=map(int,v.get('osisID').split('.')[1:])
        words=[]; text=''
        def walk(e,skipnote=False):
            nonlocal text
            tag=e.tag.replace(NS,'')
            if tag=='note': return
            if tag=='w':
                s=''.join(e.itertext()).replace('/','')
                words.append(s); text+=s
                if e.tail and e.tail.strip()=='' and e.tail: text+=' '
                return
            if tag=='seg':
                s=''.join(e.itertext()); text+=s
                if e.tail and e.tail.strip()=='' and e.tail: text+=' '
                return
            for ch in e: walk(ch)
        for ch in v: walk(ch)
        out[(c,vn)]=(words,text)
    return out
import sys; sys.path.insert(0,'.')
from acc import Mod
HM=Mod('HMT-W4',39,(50,90),'big')
_d=HM.d
_T=13138394; _n=23214; _S0=_T+4*_n
_E=struct.unpack('>%dI'%_n,_d[_T:_T+4*_n])
BLOB=_d[_S0:_S0+_E[-1]]
def vblob(i): return BLOB[(_E[i-1] if i>0 else 0):_E[i]]
SLOTS=[]
for b in range(39):
    for ci,(s,n) in enumerate(HM.book_chapters(b)):
        for k in range(n): SLOTS.append((b,ci+1,k+1,s-1+k))
HLET=dict(zip('abgdhwzjfyklmnsopxqrcvtKMNPX','אבגדהוזחטיכלמנסעפצקרששתךםןףץ'))
def ycl(bs):
    out=[]; pre=b''
    for x in bs:
        ch=chr(x)
        if ch in HLET: out.append([ch,b''])
        elif out: out[-1][1]+=bytes([x])
        else: pre+=bytes([x])
    return pre,out
def ucl(s):
    out=[]; pre=''
    for ch in ud.normalize('NFD',s):
        if 'א'<=ch<='ת': out.append([ch,''])
        elif out: out[-1][1]+=ch
        else: pre+=ch
    return pre,out
def hkey(let,mk): return ((let if let in 'cv' else ''),mk)
