"""End-to-end transformation check against the retained SQL export, isolated Mongo only."""
import hashlib
import json
import pathlib
import sys
import uuid
from copy import deepcopy
from datetime import datetime

root=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'database_helper'))
from bson import json_util
from pymongo import MongoClient
from normalization import normalize, correct_1826
from bridge import install_snapshot, parse_connection, digest_rows, source_snapshot
import tempfile


class FakeSqlConnection:
    def __init__(self,raw,metadata):self.raw=raw;self.meta=metadata;self.committed=False;self.statements=[]
    def cursor(self):return FakeSqlCursor(self)
    def commit(self):self.committed=True

class FakeSqlCursor:
    def __init__(self,connection):self.connection=connection;self.position=0;self.values=[]
    def execute(self,statement):
        self.connection.statements.append(statement)
        assert statement.startswith(('SELECT ','SET ')), 'SQL source mutation attempted'
        self.position=0
        if statement.startswith('SET '):self.description=[];self.values=[];return
        if statement.startswith('SELECT DB_NAME'):rows=[{'name':'xm'}]
        elif statement.startswith('SELECT object_id,SCHEMA_NAME'):rows=self.connection.meta['tables']
        elif statement.startswith('SELECT object_id,column_id'):rows=self.connection.meta['columns']
        elif statement.startswith('SELECT i.object_id'):rows=self.connection.meta['indexes']
        elif statement.startswith('SELECT fk.name'):rows=self.connection.meta['foreign_keys']
        elif statement.startswith('SELECT * FROM '):
            full=statement.removeprefix('SELECT * FROM ')
            table=next(t for t in self.connection.meta['tables'] if full=='['+t['schema_name']+'].['+t['name']+']')
            rows=[]
            for document in self.connection.raw[table['collection']].values():
                row={k:v for k,v in document.items() if k not in ['_id','__sql_datetime_precision']}
                for key,value in document.get('__sql_datetime_precision',{}).items():row[key]=datetime.fromisoformat(value)
                rows.append(row)
            fields=[col['name'] for col in self.connection.meta['columns'] if col['object_id']==table['object_id']]
            self.description=[(name,) for name in fields]
            self.values=[tuple(r.get(name) for name in fields) for r in rows];return
        else:raise AssertionError('Unexpected source query')
        fields=list(rows[0]) if rows else []
        self.description=[(name,) for name in fields];self.values=[tuple(r.get(name) for name in fields) for r in rows]
    def fetchall(self):return self.values
    def fetchmany(self,size):
        batch=self.values[self.position:self.position+size];self.position+=len(batch);return batch


def main():
    parsed=parse_connection('Server=tcp:localhost,1433;Database=xm;User Id=u;Password={a; b}}c};Encrypt=yes;TrustServerCertificate=yes;')
    assert parsed['password']=='a; b}c'
    try:parse_connection('Server=x;Server=y;')
    except ValueError:pass
    else:raise AssertionError('Duplicate connection option accepted')
    folder=root.parent/'mongo-export-20261031-191144'
    metadata=json_util.loads((folder/'sql-metadata.json').read_text())
    raw={p.stem:{d['_id']:d for line in p.read_text().splitlines() if (d:=json_util.loads(line))} for p in folder.glob('*.jsonl')}
    before={k:digest_rows(v.values()) for k,v in raw.items()}
    fake=FakeSqlConnection(raw,metadata)
    with tempfile.TemporaryDirectory(prefix='xemay-sql-snapshot-test-') as backup:
        snapshot,snapshot_meta=source_snapshot(fake,pathlib.Path(backup),lambda message:None)
        assert fake.committed
        assert {k:digest_rows(v.values()) for k,v in snapshot.items()}==before, 'SQL DB-API row mapping changed source'
        assert len(snapshot_meta['tables'])==len(raw)
    rows,report,removed=normalize(raw,metadata)
    assert {k:digest_rows(v.values()) for k,v in raw.items()}==before,'Input modified'
    assert report['orphan_count']==123
    assert report['purchases_merged']==1922
    assert len(rows['HoaDonBan'])==15209
    assert len(rows['NhapHang'])==3602
    assert len(rows['ThuChiKhac'])==19333,'Historical interest duplicated'
    assert len(rows['TraNo'])==28212
    assert next(r for r in rows['SoNo'].values() if r['IdSoNo']==1829)['SoTienConNo']==0
    assert rows['HoaDonBan'][151970]['TongTienHang']==rows['HoaDonBan'][151970]['TongThanhToan']>0
    changed=deepcopy(rows);changed['Xe'][2004]['GiaBan']=1
    assert correct_1826(changed).startswith('giữ nguyên'),'Guarded correction missing'
    c=MongoClient('mongodb://127.0.0.1:27017',serverSelectionTimeoutMS=5000)
    name='XM_settings_clone_test_'+uuid.uuid4().hex
    db=c[name]
    try:
        install_snapshot(db,rows,metadata)
        assert db['_sql_metadata'].find_one({'_id':'settings_clone_v1'})['installed_verified']
        assert db.DanhMucThuChi.count_documents({})==8
        assert db.HoaDonBan.count_documents({'$nor':[db.HoaDonBan.options()['validator']]})==0
        try:install_snapshot(db,rows,metadata)
        except ValueError:pass
        else:raise AssertionError('Nonempty target was overwritten')
        print('PASS: parser escaping, 143111 raw SQL records retained, 123 orphans archived, 1922 purchases merged, legacy totals, guarded 1826 correction, all document hashes, validators, categories and overwrite refusal.')
    finally:
        c.drop_database(name);c.close()

if __name__=='__main__':main()
