import sys,os,re
sys.path.insert(0,os.path.expanduser('~/cprtest')); from cpr import refs
cpr=sys.argv[1]; proj=os.path.dirname(os.path.abspath(cpr))
idx={}
for r,ds,fs in os.walk(proj):
    for f in fs: idx.setdefault(f,[]).append(os.path.join(r,f))
u=sorted(set(refs(cpr))); found=[];missing=[]
for d,f in u:
    sub=re.split(r'[/\\]',d.rstrip('/\\'))[-1]
    cand=os.path.join(proj,sub,f)
    if os.path.exists(cand): found.append((d,f,'同じ場所')); continue
    if f in idx: found.append((d,f,'別フォルダ:'+os.path.relpath(idx[f][0],proj))); continue
    missing.append((d,f))
print(os.path.basename(cpr),': 参照',len(u),' 見つかった',len(found),' 見つからない',len(missing))
from collections import Counter
print(' 見つかった場所:',Counter(x[2].split(':')[0] for x in found))
for m in missing[:20]: print('  欠:',m)
