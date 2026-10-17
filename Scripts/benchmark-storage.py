#!/usr/bin/env python3
"""Deterministic SQLite query microbenchmark, NOT a Swift/UI latency benchmark.

Mirrors the repository's fixed one-term queries and dedup predicates at the review
base and current index design. Uses synthetic data only, an in-memory SQLite db,
5 warm repetitions, median wall time. Run on the same machine for comparisons.
"""
import hashlib
import json
import platform
import sqlite3
import statistics
import time

BASE_DEDUP = '''SELECT id FROM clips WHERE type = ? AND payload = ?
 AND ((app IS NULL AND ? IS NULL) OR app = ?) ORDER BY created_at DESC LIMIT 1'''
HASH_DEDUP = '''SELECT id FROM clips WHERE payload_hash = ? AND type = ? AND payload = ?
 AND ((app IS NULL AND ? IS NULL) OR app = ?) ORDER BY created_at DESC LIMIT 1'''
ASCII = '''SELECT clips.* FROM clips WHERE (clips.id IN
 (SELECT clip_id FROM clips_fts WHERE clips_fts MATCH ?)
 OR LOWER(COALESCE(clips.note, '')) LIKE ? ESCAPE '\\')
 ORDER BY clips.pinned DESC, clips.created_at DESC LIMIT 200'''
CJK = '''SELECT clips.* FROM clips WHERE (clips.id IN
 (SELECT clip_id FROM clips_fts WHERE clips_fts MATCH ?) OR clips.id IN
 (SELECT clip_id FROM clips_fts WHERE LOWER(COALESCE(title,'')) LIKE ? ESCAPE '\\'
 OR LOWER(COALESCE(body,'')) LIKE ? ESCAPE '\\' OR LOWER(COALESCE(tags,'')) LIKE ? ESCAPE '\\')
 OR LOWER(COALESCE(clips.note,'')) LIKE ? ESCAPE '\\')
 ORDER BY clips.pinned DESC, clips.created_at DESC LIMIT 200'''


def fixture(n):
    db = sqlite3.connect(':memory:')
    db.executescript('''CREATE TABLE clips(id TEXT PRIMARY KEY,type TEXT NOT NULL,app TEXT,
 created_at REAL NOT NULL,pinned INTEGER NOT NULL DEFAULT 0,tags TEXT NOT NULL DEFAULT '[]',
 title TEXT,payload BLOB NOT NULL,note TEXT NOT NULL DEFAULT '',payload_hash TEXT);
 CREATE INDEX idx_clips_created_at ON clips(created_at DESC);
 CREATE INDEX idx_clips_type ON clips(type);
 CREATE INDEX idx_clips_pinned ON clips(pinned,created_at DESC);
 CREATE VIRTUAL TABLE clips_fts USING fts5(clip_id UNINDEXED,title,body,tags,tokenize='porter unicode61');''')
    rows, fts = [], []
    for i in range(n):
        body = f'entry {i} ' + ('needle 客户回访记录 ' if i % 97 == 0 else 'ordinary 常规记录 ') + 'x' * 480
        payload = json.dumps({'body':body}, ensure_ascii=False).encode()
        rows.append((str(i),'text','com.example.Editor',float(i),0,'[]',body[:80],payload,'',hashlib.sha256(payload).hexdigest()))
        fts.append((str(i),body[:80],body,''))
    db.executemany('INSERT INTO clips VALUES(?,?,?,?,?,?,?,?,?,?)',rows)
    db.executemany('INSERT INTO clips_fts VALUES(?,?,?,?)',fts)
    db.commit()
    return db, rows[n//2][7]


def timed(db, sql, args=()):
    db.execute(sql,args).fetchall()  # warmup
    samples=[]
    for _ in range(5):
        start=time.perf_counter()
        result=db.execute(sql,args).fetchall()
        samples.append((time.perf_counter()-start)*1000)
    return {'median_ms':round(statistics.median(samples),3),'rows':len(result)}


def main():
    output={'scope':'SQLite microbenchmark; excludes Swift, image decoding, UI and disk I/O',
            'platform':platform.platform(),'sqlite':sqlite3.sqlite_version,
            'base':'43d72cd84a5bdae2954d895c7e058db696754a87','repetitions':5,'results':[]}
    for n in [1000,10000,50000]:
        db,payload=fixture(n)
        entry={'history_count':n}
        for variant in ['before','after']:
            if variant=='after':
                db.execute('CREATE INDEX idx_clips_dedup_hash ON clips(payload_hash,type,app)')
                dedup,args=HASH_DEDUP,(hashlib.sha256(payload).hexdigest(),'text',payload,'com.example.Editor','com.example.Editor')
            else:
                dedup,args=BASE_DEDUP,('text',payload,'com.example.Editor','com.example.Editor')
            entry[variant]={
                'dedup':timed(db,dedup,args),
                'recent_200':timed(db,'SELECT * FROM clips ORDER BY created_at DESC LIMIT 200'),
                'ascii':timed(db,ASCII,('"needle"','%needle%')),
                'cjk':timed(db,CJK,('"回访"','%回访%','%回访%','%回访%','%回访%'))}
        output['results'].append(entry)
        db.close()
    print(json.dumps(output,ensure_ascii=False,indent=2))

if __name__=='__main__': main()
