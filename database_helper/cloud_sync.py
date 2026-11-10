"""Verified MongoDB snapshots; never overwrite an existing database."""
import hashlib
import re
import uuid
from datetime import datetime, timezone
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode, unquote
from bson import BSON
from pymongo import MongoClient, IndexModel
from pymongo.read_preferences import ReadPreference
from pymongo.write_concern import WriteConcern


def snapshot_uri(uri, name):
    parts = urlsplit(uri)
    query = parse_qsl(parts.query, keep_blank_values=True)
    if '@' in parts.netloc and not any(k.lower() == 'authsource' for k, _ in query):
        # SRV TXT records normally authenticate against admin.
        default = 'admin' if parts.scheme == 'mongodb+srv' else unquote(parts.path.lstrip('/')) or 'admin'
        query.append(('authSource', default))
    return urlunsplit((parts.scheme, parts.netloc, '/' + name, urlencode(query), ''))


def fingerprint(collection):
    digest = hashlib.sha256()
    count = 0
    for document in collection.find().sort('_id', 1).batch_size(500):
        digest.update(BSON.encode(document))
        count += 1
    return count, digest.hexdigest()


def collection_specs(db):
    specs = {}
    for spec in db.list_collections():
        if spec['name'].startswith('system.'):
            continue
        if spec.get('type', 'collection') != 'collection':
            raise ValueError('Chưa hỗ trợ đồng bộ view hoặc time series. Dữ liệu gốc được giữ nguyên.')
        specs[spec['name']] = spec.get('options', {})
    return specs


def copy_snapshot(source, target, progress):
    specs = collection_specs(source)
    if not specs:
        raise ValueError('Database nguồn chưa có dữ liệu để đồng bộ.')
    if target.list_collection_names():
        raise ValueError('Database đích đã tồn tại; không ghi đè dữ liệu.')
    fingerprints = {}
    indexes = {}
    total = 0
    for name, options in specs.items():
        # Unknown options fail explicitly rather than silently losing validators.
        if any(key not in ('validator', 'validationLevel', 'validationAction', 'collation') for key in options):
            raise ValueError('Collection có tùy chọn chưa hỗ trợ đồng bộ: ' + name)
        target.create_collection(name, **options)
        indexes[name] = list(source[name].list_indexes())
        batch = []
        digest = hashlib.sha256()
        count = 0
        for document in source[name].find().sort('_id', 1).batch_size(500):
            digest.update(BSON.encode(document))
            batch.append(document)
            count += 1
            if len(batch) >= 500:
                target[name].insert_many(batch)
                batch = []
        if batch:
            target[name].insert_many(batch)
        models = []
        for index in indexes[name]:
            if index['name'] == '_id_':
                continue
            settings = {k: v for k, v in index.items() if k not in ('v', 'key', 'ns', 'background')}
            models.append(IndexModel(list(index['key'].items()), **settings))
        if models:
            target[name].create_indexes(models)
        fingerprints[name] = (count, digest.hexdigest())
        if fingerprint(target[name]) != fingerprints[name]:
            raise ValueError('Đối chiếu dữ liệu không khớp: ' + name)
        total += count
        progress(f'Đã sao chép và đối chiếu {name}: {count} dòng')
    # A source edited during copying is not accepted as a complete backup.
    if collection_specs(source) != specs:
        raise ValueError('Cấu trúc dữ liệu nguồn đã thay đổi. Dừng nhập liệu và đồng bộ lại.')
    for name in specs:
        if fingerprint(source[name]) != fingerprints[name] or list(source[name].list_indexes()) != indexes[name]:
            raise ValueError('Dữ liệu nguồn đã thay đổi. Dừng nhập liệu và đồng bộ lại.')
    return {'collections': len(specs), 'rows': total}


def sync_cloud(request, progress, client_factory=MongoClient):
    source = target = None
    try:
        source = client_factory(request['sourceUri'], serverSelectionTimeoutMS=15000, socketTimeoutMS=120000)
        target = client_factory(request['targetUri'], serverSelectionTimeoutMS=15000, socketTimeoutMS=120000)
        source.admin.command('ping')
        target.admin.command('ping')
        src = source.get_default_database('XM').with_options(read_preference=ReadPreference.PRIMARY)
        base = target.get_default_database('XM').name
        if src.name in ('admin', 'config', 'local') or base in ('admin', 'config', 'local'):
            raise ValueError('Không đồng bộ database hệ thống.')
        name = re.sub('[^A-Za-z0-9_]', '_', base.split('_sync_')[0])[:24] + '_sync_' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
        dst = target[name].with_options(read_preference=ReadPreference.PRIMARY,
                                        write_concern=WriteConcern(w='majority'))
        # UUID destination is exclusively owned by this operation. Failed snapshots
        # remain unselected; retain them for diagnosis rather than dropping databases.
        report = copy_snapshot(src, dst, progress)
        report.update(database=name, mongoUri=snapshot_uri(request['targetUri'], name))
        return report
    finally:
        if source is not None:
            source.close()
        if target is not None:
            target.close()
