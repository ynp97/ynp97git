from pathlib import Path
import numpy as np, xml.etree.ElementTree as ET, copy, math, json, shutil
from fractions import Fraction
out=Path('/Users/yoshiakinagumo/Documents/Obsidian Vault/制作物/FCP/2026-09-15_無音カット')
src=Path('/private/tmp/souten-before-20260915.fcpxmld/Info.fcpxml')
shutil.copy2(src,out/'編集前.fcpxml')
db=np.load('/private/tmp/souten-cut-20260915/db.npy')
mask=db < -45
edges=np.diff(np.r_[False,mask,False].astype(int))
starts=np.where(edges==1)[0]; ends=np.where(edges==-1)[0]
rem=[]
for a,b in zip(starts,ends):
 if b-a>=80:
  lo=math.ceil((a*.01+.25)*60);hi=math.floor((b*.01-.25)*60)
  if hi>lo: rem.append((lo,hi))
tree=ET.parse(src); root=tree.getroot(); project=root.find('.//project'); seq=project.find('sequence'); spine=seq.find('spine')
assert len(spine)==1 and spine[0].tag=='asset-clip'
clip=copy.deepcopy(spine[0]);total=int(Fraction(seq.get('duration')[:-1])*60)
keep=[];cur=0
for lo,hi in rem:
 assert cur<=lo<hi<=total
 keep.append((cur,lo));cur=hi
keep.append((cur,total))
for c in list(spine):spine.remove(c)
pos=0
for a,b in keep:
 c=copy.deepcopy(clip); c.set('offset',f'{pos}/60s');c.set('start',f'{a}/60s');c.set('duration',f'{b-a}/60s');spine.append(c);pos+=b-a
seq.set('duration',f'{pos}/60s')
project.set('name','早天20260914_無音カット')
for key in ['uid','modDate']:project.attrib.pop(key,None)
root.find('.//event').attrib.pop('uid',None)
lib=root.find('library')
for c in list(lib):
 if c.tag=='smart-collection':lib.remove(c)
ET.indent(tree)
p=out/'無音カット.fcpxml'
p.write_bytes(b'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE fcpxml>\n'+ET.tostring(root,encoding='utf-8'))
assert pos+sum(b-a for a,b in rem)==total
for a,b in rem: assert np.max(db[math.ceil(a/60/.01):math.floor(b/60/.01)]) < -45
report={'threshold_db':-45,'minimum_silence_seconds':.8,'padding_each_side_seconds':.25,'cuts':len(rem),'clips':len(keep),'original_seconds':total/60,'result_seconds':pos/60,'removed_seconds':(total-pos)/60,'removed_source_ranges_seconds':[[a/60,b/60] for a,b in rem]}
(out/'解析結果.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print({k:v for k,v in report.items() if k!='removed_source_ranges_seconds'})
print(p)
