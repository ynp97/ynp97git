from pathlib import Path
import re,json
root=Path('/Users/yoshiakinagumo/Documents/Obsidian Vault')
data={}
for p in (root/'.agents/skills/st97/references').glob('2026-*.md'):
 for day,passage in re.findall(r'^\|\s*(\d{1,2})\s*\|\s*([^|]+)\|',p.read_text(),re.M):
  data[f'{p.stem}-{int(day):02d}']=passage.strip()
out=Path(__file__).resolve().parent
(out/'passages.js').write_text('window.PASSAGES = '+json.dumps(data,ensure_ascii=False,indent=2)+';\n')
print(f'{len(data)} days loaded')
