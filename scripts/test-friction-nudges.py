#!/usr/bin/env python3
"""AF-890: actual SQL nudge signal, with peer-traffic and progress controls."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
script=Path(sys.argv.pop(1)) if len(sys.argv)>1 else Path(__file__).with_name('friction_themes.py')
spec=importlib.util.spec_from_file_location('themes',script)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class Nudges(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.old_home=os.environ.get('AMUX_HOME');os.environ['AMUX_HOME']=self.temp.name
        self.db=sqlite3.connect(':memory:');self.db.row_factory=sqlite3.Row
        self.db.execute('CREATE TABLE cmd_history(session TEXT,type TEXT,origin TEXT,ts INTEGER)')
        self.db.execute('CREATE TABLE issues(session TEXT,closed_at REAL,status TEXT,updated REAL)')
        self.now=1789311600000
    def tearDown(self):
        self.db.close()
        if self.old_home is None:os.environ.pop('AMUX_HOME',None)
        else:os.environ['AMUX_HOME']=self.old_home
        self.temp.cleanup()
    def add(self,n,kind='pickup',origin='board-drive',lane='mixpeek-security'):
        self.db.executemany('INSERT INTO cmd_history VALUES(?,?,?,?)',[(lane,kind,origin,self.now-1000)]*n)
    def scan(self):return m.signal_nudge_without_movement(self.db,self.now)[0]
    def test_peer_collaboration_cannot_cross_the_nudge_threshold(self):
        self.add(8);self.add(8,'session','mixpeek-general')
        s=self.scan()
        self.assertTrue(s.measured);self.assertEqual(s.n_considered,16)
        self.assertEqual(s.value,0);self.assertFalse(s.active)
        self.assertEqual(s.detail['total_nudge_msgs'],8)
        self.assertEqual(s.detail['other_machine_msgs'],8)
        events=[json.loads(x) for x in (Path(self.temp.name)/'logs/friction-sweep.log').read_text().splitlines()]
        self.assertEqual(events[-1]['event'],'friction_nudge_population')
        self.assertEqual(events[-1]['n_considered'],16)
        self.assertEqual(events[-1]['other_machine_msgs'],8)
    def test_ten_real_nudges_remain_visible_and_scope_is_measured(self):
        self.add(10);s=self.scan()
        self.assertEqual(s.value,1);self.assertTrue(s.active)
        self.assertEqual(s.evidence[0]['nudge_msgs'],10)
        self.assertEqual(s.repo_scope,'mixpeek')
    def test_terminal_completion_remains_a_control(self):
        self.add(10)
        self.db.execute('INSERT INTO issues VALUES(?,?,?,?)',('mixpeek-security',self.now/1000-1,'done',self.now/1000-1))
        self.assertFalse(self.scan().active)
    def test_nonterminal_change_is_not_claimed_as_zero_movement(self):
        self.add(10)
        self.db.execute('INSERT INTO issues VALUES(?,?,?,?)',('mixpeek-security',None,'backlog',self.now/1000-1))
        s=self.scan()
        self.assertEqual(s.value,1)
        self.assertIn('terminal completion',s.headline)
        self.assertFalse(s.detail['nonterminal_movement_measured'])
        self.assertEqual(s.evidence[0]['cards_closed_in_window'],0)
    def test_peer_messages_alone_never_become_nudges(self):
        self.add(30,'session','ts-gke');self.assertFalse(self.scan().active)
if __name__=='__main__':unittest.main()
