import base64, datetime as dt, json, os, struct, sys, tempfile, time, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import morning

def qt_blob(major=3):
    rect = struct.pack('>iiii', 10, 20, 409, 619)
    body = rect + rect + struct.pack('>i', 0) + b'\x01\x00' + struct.pack('>i', 1440)
    if major >= 2:
        body += rect
    return struct.pack('>IHH', 0x1D9D0CB, major, 0) + body

class MorningTests(unittest.TestCase):
    def test_find_prefers_today_ipad_then_newest(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            day = dt.date(2026, 9, 29)
            for name in ('20260928_x_早天_iPad.pdf', '20260929_x_早天.pdf', 'memo.pdf'):
                (Path(a) / name).write_bytes(b'%PDF')
            self.assertEqual(morning.find_today_pdf(day, [Path(a), Path(b)]).name, '20260929_x_早天.pdf')
            ipad = Path(b) / '20260929_x_早天_iPad.pdf'; ipad.write_bytes(b'%PDF')
            self.assertEqual(morning.find_today_pdf(day, [Path(a), Path(b)]), ipad)
            newer = Path(a) / '20260929_x_早天_iPad (1).pdf'; newer.write_bytes(b'%PDF2')
            os.utime(newer, (time.time() + 60,) * 2)
            self.assertEqual(morning.find_today_pdf(day, [Path(a), Path(b)]), newer)
            self.assertIsNone(morning.find_today_pdf(dt.date(2026, 10, 1), [Path(a), Path(b)]))

    def test_stage_copies_and_clears_stale(self):
        with tempfile.TemporaryDirectory() as src, tempfile.TemporaryDirectory() as dst:
            day = dt.date(2026, 9, 29)
            (Path(src) / '20260929_早天_iPad.pdf').write_bytes(b'%PDF-today')
            morning.stage_today_pdf(dst, day, [Path(src)])
            self.assertEqual((Path(dst) / 'today.pdf').read_bytes(), b'%PDF-today')
            self.assertEqual(json.loads((Path(dst) / 'today.json').read_text())['date'], '2026-09-29')
            morning.stage_today_pdf(dst, dt.date(2026, 9, 30), [Path(src)])
            self.assertFalse((Path(dst) / 'today.pdf').exists())
            self.assertFalse((Path(dst) / 'today.json').exists())

    def test_plan_splits_left_reader_right_obs(self):
        p = morning.plan((32, 25, 1340, 863))
        self.assertEqual(p['reader'], (32, 25, 635, 888))
        self.assertEqual(p['obs'], (635, 25, 1372, 888))

    def test_geometry_rewrite_keeps_other_fields(self):
        for major in (1, 2, 3):
            out = morning.rewrite_qt_geometry(qt_blob(major), (635, 25, 1372, 888))
            self.assertEqual(struct.unpack('>iiii', out[8:24]), (635, 25, 1371, 887))
            self.assertEqual(struct.unpack('>iiii', out[24:40]), (635, 53, 1371, 887))
            self.assertEqual(out[44:46], b'\x00\x00')
            self.assertEqual(struct.unpack('>i', out[46:50])[0], 1440)
            if major >= 2:
                self.assertEqual(struct.unpack('>iiii', out[50:66]), (635, 53, 1371, 887))
            self.assertEqual(len(out), len(qt_blob(major)))
        self.assertIsNone(morning.rewrite_qt_geometry(b'junk' * 20, (0, 0, 1, 1)))

    def test_obs_ini_only_geometry_line_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            ini = Path(tmp) / 'user.ini'
            original = base64.b64encode(qt_blob()).decode()
            ini.write_text('[General]\ngeometry=keep\n[BasicWindow]\nDockState=abc\ngeometry=' + original + '\nPreviewEnabled=true\n')
            self.assertIsNone(morning.set_obs_geometry((635, 25, 1372, 888), ini, Path(tmp) / 'bk'))
            lines = ini.read_text().splitlines()
            self.assertEqual(lines[1], 'geometry=keep')
            self.assertEqual(lines[3], 'DockState=abc')
            self.assertEqual(lines[5], 'PreviewEnabled=true')
            self.assertNotEqual(lines[4], 'geometry=' + original)
            self.assertTrue((Path(tmp) / 'bk/user_before_layout.ini').exists())

    def test_reader_uses_dedicated_app_and_position(self):
        cmd = morning.reader_command('http://127.0.0.1:19797/reader', (32, 25, 635, 888), Path('/x/早天原稿.app'))
        self.assertEqual(cmd, ['/x/早天原稿.app/Contents/MacOS/soten-reader',
                               'http://127.0.0.1:19797/reader', '32', '25', '603', '863'])

if __name__ == '__main__':
    unittest.main()
