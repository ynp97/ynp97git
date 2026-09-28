import datetime as dt
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import Broadcast, find_vault

class RecoveryTests(unittest.TestCase):
    def test_restart_preserves_current_page_and_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            storage = Path(tmp) / 'extra_pages.json'
            a = Broadcast(find_vault(), storage)
            a.action({'action':'prepare','date':'2026-09-28'})
            a.action({'action':'next'})
            b = Broadcast(find_vault(), storage)
            self.assertEqual((b.state['date'], b.state['mode'], b.state['page']), ('2026-09-28','body',1))
            a.action({'action':'add_extra','title':'test','text':'test page'})
            ident = a.snapshot()['extras'][0]['id']
            a.action({'action':'show_extra','id':ident})
            b = Broadcast(find_vault(), storage)
            self.assertEqual(b.snapshot()['extraSelected']['id'], ident)

    def test_previous_day_session_and_corrupt_file_not_restored(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'session.json'
            path.write_text(json.dumps(dict(saved_on='2000-01-01', date='2026-09-25', mode='hidden',page=0)))
            a = Broadcast(find_vault(), Path(tmp) / 'extra_pages.json')
            self.assertEqual(a.state['date'],dt.date.today().isoformat())
            path.write_text('broken')
            self.assertEqual(Broadcast(find_vault(), Path(tmp) / 'extra_pages.json').state['date'], dt.date.today().isoformat())
