"""Exercise the shipped v4 SQL on SQLite; GRDB migration replay is covered by XCTest."""
from pathlib import Path
import re
import sqlite3
import unittest

SOURCE = (Path(__file__).resolve().parents[2] / 'Sources/Magpie/Storage/Database.swift').read_text()


def statements(version):
    body = SOURCE.split(f'registerMigration("{version}")', 1)[1].split('migrator.registerMigration', 1)[0]
    # v4's first block is pure SQL; Swift repair/backfill is validated on macOS.
    body = body.split('// Repair rows', 1)[0]
    pattern = r'try db.execute\(sql: (?:"""(.*?)"""|"([^"\n]*)")\)'
    return [a or b for a, b in re.findall(pattern, body, re.S)]


class MigrationSQLTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        for name in ['v1_initial', 'v2_snippets', 'v3_clip_notes']:
            for sql in statements(name):
                self.db.executescript(sql)
        self.db.execute("INSERT INTO clips(id,type,created_at,pinned,tags,title,payload,note) VALUES('kept','text',1,1,'[\"tag\"]','title',X'7B7D','kept note')")
        self.db.executemany('INSERT INTO clips_fts(clip_id,title,body,tags) VALUES(?,?,?,?)', [
            ('kept', 'title', 'retained text', 'tag'),
            ('kept', 'duplicate', 'stale duplicate', ''),
            ('deleted', 'orphan', 'deleted synthetic secret', '')])
        self.db.commit()
        for sql in statements('v4_fts_cleanup'):
            self.db.executescript(sql)

    def tearDown(self):
        self.db.close()

    def test_upgrade_removes_orphan_and_duplicate_without_modifying_payload(self):
        self.assertEqual(self.db.execute('SELECT pinned,tags,payload,note FROM clips').fetchone(),
                         (1, '["tag"]', b'{}', 'kept note'))
        self.assertEqual(self.db.execute('SELECT clip_id,body FROM clips_fts').fetchall(), [('kept', 'retained text')])
        self.assertEqual(self.db.execute("SELECT count(*) FROM clips_fts WHERE clips_fts MATCH 'secret'").fetchone()[0], 0)

    def test_delete_trigger_and_rollback_are_atomic(self):
        self.db.execute('DELETE FROM clips')
        self.assertEqual(self.db.execute('SELECT count(*) FROM clips_fts').fetchone()[0], 0)
        self.db.rollback()
        self.assertEqual(self.db.execute('SELECT count(*) FROM clips').fetchone()[0], 1)
        self.assertEqual(self.db.execute('SELECT count(*) FROM clips_fts').fetchone()[0], 1)
        self.db.execute('DELETE FROM clips')
        self.db.commit()
        self.assertEqual(self.db.execute('SELECT count(*) FROM clips_fts').fetchone()[0], 0)

    def test_vacuum_does_not_break_fts_identity(self):
        self.db.execute('VACUUM')
        self.db.execute('DELETE FROM clips')
        self.assertEqual(self.db.execute('SELECT count(*) FROM clips_fts').fetchone()[0], 0)


if __name__ == '__main__':
    unittest.main()
