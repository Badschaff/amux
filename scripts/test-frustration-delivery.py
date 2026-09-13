#!/usr/bin/env python3
"""AF-889: exercise the complete scanner query/annotation/output boundary."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve() if len(sys.argv)>1 else Path(__file__).with_name('frustration_scan.py')

class Delivery(unittest.TestCase):
    def scan(self, verdict, legacy=False):
        with tempfile.TemporaryDirectory() as folder:
            db=Path(folder)/'db';c=sqlite3.connect(db)
            c.execute('CREATE TABLE cmd_history(id INTEGER,ts INTEGER,session TEXT,text TEXT,delivery TEXT,type TEXT,origin TEXT'+('' if legacy else ',submit_verdict TEXT')+')')
            for i in [1,2]:
                values=(i,int(time.time()*1000)-i*30000,'fixture','Why is the message delivery instrument still broken','direct','user','')
                if not legacy:values+= (verdict,)
                c.execute('INSERT INTO cmd_history VALUES('+','.join('?'*len(values))+')',values)
            c.commit();c.close()
            r=subprocess.run([sys.executable,str(SCRIPT)],env=dict(os.environ,AMUX_DB=str(db),AMUX_HOME=folder),capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stderr)
            d=json.loads(r.stdout)
            rows={m['id']:m for f in d['findings'] for m in f['messages']}
            self.assertEqual(set(rows),{1,2},'fixture must exercise actual emitted candidates')
            log=Path(folder)/'logs/friction-sweep.log'
            events=[json.loads(s) for s in log.read_text().splitlines()] if log.exists() else []
            return d,rows,events

    def test_stuck_is_not_delivered_and_self_announces(self):
        d,rows,events=self.scan('stuck')
        self.assertEqual({r['delivered'] for r in rows.values()},{'not delivered'})
        self.assertTrue(all(r['submit_verdict']=='stuck' for r in rows.values()))
        self.assertFalse(any(f['kind']=='double-delivery' for f in d['findings']))
        self.assertEqual(events[-1]['event'],'friction_direct_submission_unconfirmed')
        self.assertEqual(events[-1]['n_considered'],2)
        self.assertEqual(events[-1]['unconfirmed_direct'],2)

    def test_confirmed_remains_delivered(self):
        d,rows,_=self.scan('confirmed')
        self.assertEqual({r['delivered'] for r in rows.values()},{'delivered'})
        self.assertTrue(any(f['kind']=='double-delivery' for f in d['findings']))

    def test_retry_success_remains_delivered(self):
        _,rows,_=self.scan('retried')
        self.assertEqual({r['delivered'] for r in rows.values()},{'delivered'})

    def test_unverified_is_unknown(self):
        _,rows,_=self.scan('unverified')
        self.assertEqual({r['delivered'] for r in rows.values()},{'unknown'})

    def test_missing_verdict_is_unknown(self):
        _,rows,_=self.scan(None)
        self.assertEqual({r['delivered'] for r in rows.values()},{'unknown'})

    def test_future_verdict_is_unknown(self):
        _,rows,_=self.scan('new-future-state')
        self.assertEqual({r['delivered'] for r in rows.values()},{'unknown'})

    def test_legacy_schema_remains_readable_but_unknown(self):
        _,rows,_=self.scan(None,legacy=True)
        self.assertEqual({r['delivered'] for r in rows.values()},{'unknown'})

if __name__=='__main__':unittest.main()
