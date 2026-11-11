"""Exercise real configured MongoDB endpoints using isolated disposable databases.

Reads macOS connection settings into memory; never prints or saves credentials.
Does not change application settings or the business databases.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'database_helper'))
from pymongo import MongoClient
from cloud_sync import compare_databases, sync_cloud, snapshot_uri, version_database, collection_specs, fingerprint
from diagnostics import redact


def saved_connections():
    local = os.environ.get('XEMAY_LOCAL_URI')
    cloud = os.environ.get('XEMAY_CLOUD_URI')
    if local and cloud:
        return local, cloud
    if sys.platform != 'darwin':
        raise RuntimeError('Set XEMAY_LOCAL_URI and XEMAY_CLOUD_URI to run this test.')
    result = subprocess.run(['security', 'find-generic-password', '-s', 'vn.cuahang.xemayApp.database-settings', '-a', 'connections', '-w'], capture_output=True, timeout=45)
    if result.returncode:
        raise RuntimeError('Cannot read saved connections from Keychain.')
    settings = json.loads(result.stdout)
    if not settings.get('mongoUri') or not settings.get('cloudUri'):
        raise RuntimeError('Save both MongoDB connections before running the test.')
    return settings['mongoUri'], settings['cloudUri']


def main():
    local_uri, cloud_uri = saved_connections()
    prefix = 'XT_' + uuid.uuid4().hex[:10]
    tracked = set()
    clients = {
        'local': MongoClient(local_uri, serverSelectionTimeoutMS=15000, connectTimeoutMS=8000, socketTimeoutMS=120000),
        'cloud': MongoClient(cloud_uri, serverSelectionTimeoutMS=15000, connectTimeoutMS=8000, socketTimeoutMS=120000),
    }
    report = {'at': datetime.now(timezone.utc).isoformat(), 'testPrefix': prefix, 'steps': [], 'success': False}
    def db(side, name):
        if not name.startswith(prefix + '_'):
            raise RuntimeError('Refusing to access a database outside this test.')
        if (side, name) not in tracked:
            # Do not register existing or server-rejected names for cleanup.
            if clients[side][name].list_collection_names():
                raise RuntimeError('Refusing to reuse an existing test database.')
        tracked.add((side, name))
        return clients[side][name]
    def uri_db(side, uri):
        return db(side, urlsplit(uri).path.lstrip('/'))
    class Endpoint:
        def __init__(self, side, uri):
            self.side, self.uri = side, uri
            self.admin = clients[side].admin
        def get_default_database(self, default):
            return uri_db(self.side, self.uri)
        def __getitem__(self, name):
            return db(self.side, name)
        def close(self): pass
    def transfer(source_side, source_uri, target_side, target_uri, policy):
        preview = compare_databases(uri_db(source_side, source_uri), uri_db(target_side, target_uri))
        endpoints = iter([Endpoint(source_side, source_uri), Endpoint(target_side, target_uri)])
        result = sync_cloud({
            'command': 'syncCloud', 'sourceUri': source_uri, 'targetUri': target_uri,
            'expectedSourceVersion': preview['sourceVersion']['version'],
            'expectedTargetVersion': preview['targetVersion']['version'], 'conflictPolicy': policy,
        }, lambda text: print(text, flush=True), client_factory=lambda *args, **kwargs: next(endpoints))
        source_result = uri_db(source_side, result['sourceMongoUri'])
        target_result = uri_db(target_side, result['mongoUri'])
        left, right = version_database(source_result), version_database(target_result)
        assert left['version'] == right['version'], 'Content versions differ'
        assert left['revision'] == right['revision'], 'Revision numbers differ'
        assert collection_specs(source_result) == collection_specs(target_result)
        for name in collection_specs(source_result):
            assert fingerprint(source_result[name]) == fingerprint(target_result[name]), 'BSON data differs'
        report['steps'].append({'direction': source_side + ' -> ' + target_side,
                                'rows': result['rows'], 'collections': result['collections'],
                                'conflicts': preview['conflicts'], 'revision': left['revision'],
                                'version': left['version'], 'versionsMatch': True})
        return result, source_result, target_result
    try:
        for client in clients.values(): client.admin.command('ping')
        local_name, cloud_name = prefix + '_local', prefix + '_cloud'
        # Random names plus an explicit empty check ensure no existing collection is modified.
        for side, name in [('local', local_name), ('cloud', cloud_name)]:
            db(side, name)
        local, cloud = db('local', local_name), db('cloud', cloud_name)
        local.create_collection('SanPham', validator={'$jsonSchema': {'bsonType': 'object', 'required': ['_id', 'MaSanPham'], 'properties': {'GiaBan': {'bsonType': ['int', 'long'], 'minimum': 0}}}})
        local.SanPham.create_index('MaSanPham', unique=True)
        local.SanPham.insert_many([
            {'_id': 'test-p1', 'MaSanPham': 'TEST-001', 'TenSanPham': 'Nhớt mẫu', 'GiaBan': 120000},
            {'_id': 'test-p2', 'MaSanPham': 'TEST-002', 'TenSanPham': 'Mũ bảo hiểm mẫu', 'GiaBan': 250000},
        ])
        local.KhachHang.insert_one({'_id': 'test-k1', 'TenKhachHang': 'Khách thử trên máy', 'GhiChu': 'Dữ liệu kiểm thử'})
        cloud.KhachHang.insert_one({'_id': 'test-k2', 'TenKhachHang': 'Khách thử trên cloud', 'GhiChu': 'Dữ liệu kiểm thử'})
        first, local_snapshot, cloud_snapshot = transfer('local', snapshot_uri(local_uri, local_name), 'cloud', snapshot_uri(cloud_uri, cloud_name), 'abort')
        assert first['rows'] == 4
        assert cloud_snapshot.SanPham.count_documents({}) == 2
        # Establish a change-stream checkpoint, then verify edits invalidate it.
        checkpoint = compare_databases(local_snapshot, cloud_snapshot)
        assert checkpoint['conflicts'] == 0
        cloud_snapshot.SanPham.update_one({'_id': 'test-p1'}, {'$set': {'GiaBan': 135000}})
        cloud_snapshot.SanPham.insert_one({'_id': 'test-p3', 'MaSanPham': 'TEST-003', 'TenSanPham': 'Bugi thêm trên cloud', 'GiaBan': 60000})
        second, cloud_final, local_final = transfer('cloud', first['mongoUri'], 'local', first['sourceMongoUri'], 'source')
        assert second['rows'] == 5
        assert local_final.SanPham.find_one({'_id': 'test-p1'})['GiaBan'] == 135000
        assert local_final.SanPham.count_documents({'_id': 'test-p3'}) == 1
        assert local_final.KhachHang.count_documents({}) == 2
        # Original test databases, like original business data, remain unchanged by sync.
        assert local.SanPham.find_one({'_id': 'test-p1'})['GiaBan'] == 120000
        assert cloud.KhachHang.count_documents({}) == 1
        assert local_final.SanPham.index_information()['MaSanPham_1']['unique']
        assert local_final.SanPham.options()['validator']
        report['success'] = True
    except Exception as error:
        report['errorType'] = type(error).__name__
        report['error'] = redact(str(error), {'sourceUri': local_uri, 'targetUri': cloud_uri})
    finally:
        remaining = []
        for side, name in sorted(tracked):
            try:
                if not name.startswith(prefix + '_'):
                    raise RuntimeError('Cleanup guard rejected database name')
                clients[side].drop_database(name)
            except Exception:
                remaining.append({'side': side, 'database': name})
        report['cleanupComplete'] = not remaining
        report['remainingTestDatabases'] = remaining
        report['testDatabasesCleaned'] = len(tracked) - len(remaining)
        for client in clients.values(): client.close()
        output = ROOT / 'build/test-results/cloud-sync-live.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['success'] and report['cleanupComplete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
