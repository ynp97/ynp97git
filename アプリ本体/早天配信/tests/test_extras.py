import sys,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from server import Broadcast,find_vault
import unittest

class ExtraPagesTest(unittest.TestCase):
    def test_saved_pages_and_bible_return(self):
        with tempfile.TemporaryDirectory() as d:
         path=Path(d)/'extras.json';b=Broadcast(find_vault(),path)
         b.action({'action':'prepare','date':'2026-09-26'})
         b.action({'action':'page','page':3})
         s=b.action({'action':'add_extra','reference':'ヨハネ3:16-18'})
         assert len(s['extras'][0]['pages'])>=3
         first=s['extras'][0]['id']
         b.action({'action':'add_extra','title':'説明','text':'説明の文。'*120})
         s=b.action({'action':'move_extra','id':first,'direction':'down'})
         assert s['extras'][1]['id']==first
         b.action({'action':'show_extra','id':first})
         s=b.action({'action':'next'});assert s['extraPage']==1 and s['page']==3
         s=b.action({'action':'mode','mode':'body'});assert s['page']==3
         c=Broadcast(find_vault(),path);s=c.action({'action':'prepare','date':'2026-09-26'});assert len(s['extras'])==2
         c.action({'action':'show_extra','id':first});s=c.action({'action':'remove_extra','id':first});assert s['mode']=='body'
         s=c.action({'action':'prepare','date':'2026-09-25'});assert not s['extras']
