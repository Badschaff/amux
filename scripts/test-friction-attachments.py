#!/usr/bin/env python3
"""AF-888: actual SQL signal must separate storage metadata from instructions."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

script = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).with_name('friction_themes.py')
spec = importlib.util.spec_from_file_location('themes', script)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class Attachments(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.old_home = os.environ.get('AMUX_HOME')
        os.environ['AMUX_HOME'] = self.temp.name
        self.db = sqlite3.connect(':memory:')
        self.db.row_factory = sqlite3.Row
        self.db.execute('CREATE TABLE cmd_history(id INTEGER, text TEXT, session TEXT, ts INTEGER, type TEXT, origin TEXT)')
        self.now = 1789311600000

    def tearDown(self):
        self.db.close()
        if self.old_home is None: os.environ.pop('AMUX_HOME', None)
        else: os.environ['AMUX_HOME'] = self.old_home
        self.temp.cleanup()

    def scan(self, texts):
        for i, text in enumerate(texts):
            self.db.execute('INSERT INTO cmd_history VALUES(?,?,?,?,?,?)', (i+1, text, ['amux-frustrations','mixpeek-homepage-claude'][i%2], self.now-i*1000, 'user', ''))
        return m.signal_cross_lane_repeat(self.db, self.now)[0]

    def test_unrelated_screenshot_requests_do_not_become_a_theme(self):
        s = self.scan(['Annotate homepage templates with extracted labels @/Users/ethan/.amux/uploads/abc123-image.png',
                       'Correct the overflowing mobile notification drawer @/Users/ethan/.amux/uploads/def456-image.png'])
        self.assertTrue(s.measured)
        self.assertEqual(s.n_considered, 2)
        self.assertEqual(s.value, 0)
        self.assertFalse(s.active)
        self.assertEqual(s.detail['ignored_upload_references'], 2)
        events = [json.loads(line) for line in (Path(self.temp.name)/'logs/friction-sweep.log').read_text().splitlines()]
        self.assertEqual(events[-1]['event'], 'friction_attachment_metadata_excluded')
        self.assertEqual(events[-1]['n_considered'], 2)
        self.assertEqual(events[-1]['ignored_upload_references'], 2)

    def test_real_instruction_survives_different_screenshots(self):
        ask = 'Review the queued tasks and report the unresolved blockers '
        s = self.scan([ask+'@/Users/ethan/.amux/uploads/a-image.png', ask+'@/home/ethan/.amux/uploads/b-image.png'])
        self.assertGreater(s.value, 0)
        self.assertTrue(s.active)
        self.assertTrue(any(e['cross_repo'] for e in s.evidence))
        self.assertTrue(all('uploads' not in e['phrase'] for e in s.evidence))

    def test_image_only_messages_are_not_shared_instructions(self):
        s = self.scan(['[01:36 PM] @/Users/ethan/.amux/uploads/abc123-image.png', '[02:02 PM] @/Users/ethan/.amux/uploads/abc123-image.png'])
        self.assertEqual(s.value, 0)
        self.assertEqual(s.n_considered, 2)

    def test_remaining_amux_repeat_does_not_keep_false_cross_repo_scope(self):
        ask = 'Restore the previous toolbar icons across the interface'
        for i, lane in enumerate(['amux','amux-frustrations']):
            self.db.execute('INSERT INTO cmd_history VALUES(?,?,?,?,?,?)', (i+1,ask,lane,self.now-i*1000,'user',''))
        s=m.signal_cross_lane_repeat(self.db,self.now)[0]
        self.assertGreater(s.value,0)
        self.assertEqual(s.repo_scope,'amux')

    def test_real_filesystem_instruction_is_preserved(self):
        s = self.scan(['Compare the data in /srv/customer/report.json against the acceptance totals']*2)
        self.assertGreater(s.value, 0)
        self.assertEqual(s.detail['ignored_upload_references'], 0)

if __name__ == '__main__': unittest.main()
