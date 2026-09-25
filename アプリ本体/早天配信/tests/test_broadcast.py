import copy
import sys
import unittest
from unittest.mock import patch
import datetime as dt
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import Broadcast, find_vault, prepare, read_range, schedules, split_text


class BroadcastTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vault = find_vault()

    def test_all_registered_dates_preserve_every_verse_character(self):
        for date, reference in schedules(self.vault).items():
            with self.subTest(date=date, reference=reference):
                data = prepare(self.vault, date)
                verses = read_range(self.vault, reference)
                self.assertEqual(''.join(p['text'] for p in data['pages']), ''.join(v['text'] for v in verses))
                self.assertEqual(data['verseCount'], len(verses))
                self.assertTrue(data['pages'])

    def test_cross_chapter_and_whole_chapter_ranges(self):
        self.assertEqual(prepare(self.vault, '2026-09-16')['verseCount'], 24)
        data = prepare(self.vault, '2026-09-13')
        self.assertEqual(data['pages'][0]['label'], '歴代誌第一 1:1')
        self.assertEqual(data['pages'][-1]['label'], '歴代誌第一 3:24')

    def test_invalid_date_does_not_replace_broadcast(self):
        app = Broadcast(self.vault)
        app.action({'action': 'prepare', 'date': '2026-09-25'})
        before = copy.deepcopy(app.snapshot())
        for date in ['2026-99-40', '2099-01-01', '../', '0925']:
            with self.assertRaises(ValueError):
                app.action({'action': 'prepare', 'date': date})
            self.assertEqual(before, app.snapshot())

    def test_page_bounds_and_hidden_resume(self):
        app = Broadcast(self.vault)
        app.action({'action': 'prepare', 'date': '2026-09-25'})
        self.assertEqual(app.action({'action': 'previous'})['page'], 0)
        app.action({'action': 'next'})
        hidden = app.action({'action': 'mode', 'mode': 'hidden'})
        self.assertEqual(hidden['page'], 1)
        self.assertEqual(app.action({'action': 'mode', 'mode': 'body'})['page'], 1)
        last = app.action({'action': 'page', 'page': 99999})
        self.assertEqual(last['page'], len(last['pages']) - 1)

    def test_known_source_warning(self):
        self.assertTrue(prepare(self.vault, '2026-09-25')['warnings'])
        self.assertFalse(prepare(self.vault, '2026-09-26')['warnings'])

    def test_revision_remains_exact_in_browser_json(self):
        app = Broadcast(self.vault)
        before = app.snapshot()['revision']
        after = app.action({'action': 'mode', 'mode': 'hidden'})['revision']
        self.assertIsInstance(before, str)
        self.assertNotEqual(before, after)

    def test_next_morning_launch_and_missing_month(self):
        app = Broadcast(self.vault)
        app.action({'action':'prepare','date':'2026-09-25'})
        with patch('server.dt.date') as date:
            date.today.return_value = dt.datetime(2026, 9, 26).date()
            date.fromisoformat.side_effect = lambda value: dt.datetime.strptime(value, '%Y-%m-%d').date()
            self.assertEqual(app.action({'action':'open_today'})['date'], '2026-09-26')
        with patch('server.dt.date') as date:
            date.today.return_value = dt.datetime(2099, 1, 1).date()
            date.fromisoformat.side_effect = lambda value: dt.datetime.strptime(value, '%Y-%m-%d').date()
            state = app.action({'action':'open_today'})
            self.assertEqual(state['mode'], 'hidden')
            self.assertEqual(state['pages'], [])
            self.assertTrue(state['startupError'])

    def test_long_verse_lossless(self):
        text = ('あいうえお。 かきくけこ、' * 150)
        self.assertEqual(''.join(split_text(text)), text)


if __name__ == '__main__':
    unittest.main()
