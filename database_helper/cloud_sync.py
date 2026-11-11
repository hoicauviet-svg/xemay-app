"""Verified MongoDB snapshots; never overwrite an existing database."""
from customer_addresses import migrate_database
import hashlib
import re
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock
from contextvars import copy_context
from contextlib import ExitStack
from pymongo.errors import OperationFailure
from datetime import datetime, timezone
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode, unquote
from bson import BSON
from pymongo import MongoClient, IndexModel
from pymongo.read_preferences import ReadPreference
from pymongo.write_concern import WriteConcern


def snapshot_name(base):
    # Atlas shared deployments may limit database names to 38 bytes.
    # ASCII stem (14) + separator (6) + random suffix (16) = at most 36 bytes.
    stem = re.sub('[^A-Za-z0-9_]', '_', base.split('_sync_')[0])[:14] or 'XM'
    return stem + '_sync_' + uuid.uuid4().hex[:16]


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
        if spec['name'].startswith('system.') or spec['name'] == '_app_sync_meta':
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


def schema(db, name, options):
    indexes = []
    for index in db[name].list_indexes():
        indexes.append({k: v for k, v in index.items() if k not in ('v', 'ns', 'background')})
    return {'options': options, 'indexes': sorted(indexes, key=lambda i: i['name'])}


def key_for(document):
    return bytes(BSON.encode({'_id': document['_id']}))


def documents(db, name):
    return {key_for(doc): doc for doc in db[name].find().batch_size(500)}


def scan_database(db, include_records=False, progress=None, label=''):
    specs = collection_specs(db)
    def scan_collection(name):
        digest = hashlib.sha256()
        records = {} if include_records else None
        count = 0
        description = schema(db, name, specs[name])
        # A larger batch reduces cloud round trips; no full documents are retained.
        for document in db[name].find().sort('_id', 1).batch_size(5000):
            raw = BSON.encode(document)
            digest.update(raw)
            if records is not None:
                records[key_for(document)] = hashlib.sha256(raw).digest()
            count += 1
            if progress is not None and count % 10000 == 0:
                progress(f'{label}: {name} — đã đọc {count:,} dòng')
        return name, {'count': count, 'content': digest.hexdigest(), 'schema': description, 'records': records}
    collections = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(copy_context().run, scan_collection, name) for name in specs]
        for future in as_completed(futures):
            name, result = future.result()
            collections[name] = result
            if progress is not None:
                progress(f'{label}: {len(collections)}/{len(specs)} bảng — {name}: {result["count"]:,} dòng')
    digest = hashlib.sha256()
    for name in sorted(collections):
        item = collections[name]
        digest.update(BSON.encode({'name': name, 'content': item['content'], 'schema': item['schema']}))
    return {'version': digest.hexdigest(), 'rows': sum(item['count'] for item in collections.values()), 'collections': collections}


def store_version(db, scan):
    version = scan['version']
    rows = scan['rows']
    specs = scan['collections']
    previous = db['_app_sync_meta'].find_one({'_id': 'current'}) or {}
    record = {'_id': 'current', 'version': version,
              'revision': previous.get('revision', 0) + (previous.get('version') != version),
              'observedAt': datetime.now(timezone.utc).isoformat(),
              'database': db.name, 'rows': rows, 'collections': specs if isinstance(specs, int) else len(specs)}
    if previous.get('version') == version:
        for field in ('parents', 'conflictPolicy'):
            if field in previous:
                record[field] = previous[field]
    elif previous.get('version'):
        record['parents'] = [previous['version']]
    history = {k: v for k, v in record.items() if k != '_id'}
    db['_app_sync_meta'].update_one({'_id': version}, {'$setOnInsert': history}, upsert=True)
    db['_app_sync_meta'].replace_one({'_id': 'current'}, record, upsert=True)
    return {k: v for k, v in record.items() if k != '_id'}


def version_database(db):
    return store_version(db, scan_database(db))


def open_comparison_watch(db, token=None):
    stream = None
    try:
        options = {'max_await_time_ms': 500, 'show_expanded_events': True}
        if token is not None:
            options['resume_after'] = token
        stream = db.watch([{'$match': {'ns.coll': {'$ne': '_app_sync_meta'}}}], **options)
        if stream.resume_token is None:
            stream.try_next()
        if stream.resume_token is None:
            stream.close()
            return None
        return stream
    except (OperationFailure, NotImplementedError, TypeError, AttributeError):
        if stream is not None:
            stream.close()
        # Standalone servers or accounts without change-stream permissions must
        # still perform two full passes. Never trust cached metadata alone.
        return None


def compare_databases(source, target, progress=None):
    output_lock = Lock()
    def announce(message):
        if progress is not None:
            with output_lock:
                progress(message)
    def read_side(db, label):
        previous = db['_app_sync_meta'].find_one({'_id': 'current'}) or {}
        token = previous.get('comparisonToken')
        stream = open_comparison_watch(db, token) if token is not None else None
        try:
            if stream is not None:
                event = stream.try_next()
                if event is None and isinstance(previous.get('version'), str) and isinstance(previous.get('rows'), int) and isinstance(previous.get('collections'), int):
                    announce(f'{label}: dữ liệu không thay đổi từ lần kiểm tra trước, dùng phiên bản đã xác nhận.')
                    return {'version': previous['version'], 'rows': previous['rows'], 'collections': previous['collections']}, stream
                stream.close()
            stream = open_comparison_watch(db)
            if stream is not None:
                announce(f'{label}: đang theo dõi thay đổi để không phải đọc dữ liệu lần nữa.')
            scan = scan_database(db, True, announce, label)
            return scan, stream
        except BaseException:
            if stream is not None:
                stream.close()
            raise
    announce('Đang kiểm tra phiên bản và thay đổi trên hai database…')
    with ExitStack() as cleanup:
        with ThreadPoolExecutor(max_workers=2) as pool:
            left_future = pool.submit(copy_context().run, read_side, source, 'Phía nguồn')
            right_future = pool.submit(copy_context().run, read_side, target, 'Phía đích')
            # Register streams even if one endpoint fails, so cursors are closed.
            results, error = [], None
            for future in (left_future, right_future):
                try:
                    scan, stream = future.result()
                    if stream is not None: cleanup.callback(stream.close)
                    results.append((scan, stream))
                except BaseException as failure:
                    error = failure
            if error is not None: raise error
        (left_scan, left_stream), (right_scan, right_stream) = results
        report = {'sourceOnly': 0, 'targetOnly': 0, 'conflicts': 0, 'identical': 0, 'schemaConflicts': 0}
        if left_scan['version'] == right_scan['version']:
            report['identical'] = left_scan['rows']
        else:
            # Cached hashes suffice for equal versions. Different versions need
            # actual per-record hashes to count changes and conflicts accurately.
            with ThreadPoolExecutor(max_workers=2) as pool:
                left_future = pool.submit(copy_context().run, scan_database, source, True, announce, 'Phía nguồn') if isinstance(left_scan['collections'], int) else None
                right_future = pool.submit(copy_context().run, scan_database, target, True, announce, 'Phía đích') if isinstance(right_scan['collections'], int) else None
                if left_future is not None: left_scan = left_future.result()
                if right_future is not None: right_scan = right_future.result()
            left_collections, right_collections = left_scan['collections'], right_scan['collections']
            for name in sorted(set(left_collections) | set(right_collections)):
                left_item, right_item = left_collections.get(name), right_collections.get(name)
                left = left_item['records'] if left_item is not None else {}
                right = right_item['records'] if right_item is not None else {}
                report['sourceOnly'] += len(left.keys() - right.keys())
                report['targetOnly'] += len(right.keys() - left.keys())
                for key in left.keys() & right.keys():
                    report['identical' if left[key] == right[key] else 'conflicts'] += 1
                if left_item is not None and right_item is not None and left_item['schema'] != right_item['schema']:
                    report['schemaConflicts'] += 1
                if left_item is not None: left_item['records'] = None
                if right_item is not None: right_item['records'] = None
        announce('Đang xác nhận dữ liệu không thay đổi trong lúc so sánh…')
        def verify(db, scan, stream, label):
            if stream is not None:
                if stream.try_next() is not None:
                    raise ValueError('Dữ liệu đã thay đổi khi so sánh. Vui lòng so sánh lại.')
                return scan
            checked = scan_database(db, False, announce, label)
            if checked['version'] != scan['version']:
                raise ValueError('Dữ liệu đã thay đổi khi so sánh. Vui lòng so sánh lại.')
            return checked
        # Stream cursor operations are serialized after the scan workers finish.
        # Standalone fallbacks can scan concurrently.
        with ThreadPoolExecutor(max_workers=2) as pool:
            left_future = pool.submit(copy_context().run, verify, source, left_scan, None, 'Xác nhận phía nguồn') if left_stream is None else None
            right_future = pool.submit(copy_context().run, verify, target, right_scan, None, 'Xác nhận phía đích') if right_stream is None else None
            if left_stream is not None: verify(source, left_scan, left_stream, 'Phía nguồn')
            if right_stream is not None: verify(target, right_scan, right_stream, 'Phía đích')
            if left_future is not None: left_scan = left_future.result()
            if right_future is not None: right_scan = right_future.result()
        report.update(sourceVersion=store_version(source, left_scan), targetVersion=store_version(target, right_scan))
        for db, stream in ((source, left_stream), (target, right_stream)):
            if stream is not None:
                db['_app_sync_meta'].update_one({'_id': 'current'}, {'$set': {'comparisonToken': stream.resume_token}})
        announce('Đã so sánh và xác nhận xong hai database.')
        return report


def merge_snapshot(source, target, destination, policy, progress):
    if destination.list_collection_names():
        raise ValueError('Database đích đã tồn tại; không ghi đè dữ liệu.')
    left_specs, right_specs = collection_specs(source), collection_specs(target)
    names = sorted(set(left_specs) | set(right_specs))
    if not names:
        raise ValueError('Hai database chưa có dữ liệu để đồng bộ.')
    total = 0
    for name in names:
        left = documents(source, name) if name in left_specs else {}
        right = documents(target, name) if name in right_specs else {}
        chosen = source if name in left_specs else target
        options = left_specs.get(name, right_specs.get(name))
        if name in left_specs and name in right_specs and schema(source, name, left_specs[name]) != schema(target, name, right_specs[name]):
            if policy == 'abort':
                raise ValueError('Cấu trúc hai bên khác nhau. Chọn bên ưu tiên hoặc hủy.')
            if policy == 'target':
                chosen, options = target, right_specs[name]
        if any(key not in ('validator', 'validationLevel', 'validationAction', 'collation') for key in options):
            raise ValueError('Collection có tùy chọn chưa hỗ trợ: ' + name)
        merged = dict(right)
        for key, document in left.items():
            if key in right and BSON.encode(document) != BSON.encode(right[key]):
                # Allocation counters must never move backwards after a merge.
                if name == '_app_counters' and isinstance(document.get('value'), (int, float)) and isinstance(right[key].get('value'), (int, float)):
                    merged[key] = {**document, 'value': max(document['value'], right[key]['value'])}
                    continue
                if policy == 'abort':
                    raise ValueError('Có bản ghi xung đột. Chọn bên ưu tiên hoặc hủy.')
                if policy == 'target':
                    continue
            merged[key] = document
        destination.create_collection(name, **options)
        batch = []
        for document in merged.values():
            batch.append(document)
            if len(batch) == 500:
                destination[name].insert_many(batch)
                batch = []
        if batch:
            destination[name].insert_many(batch)
        models = [IndexModel(list(index['key'].items()), **{k: v for k, v in index.items() if k != 'key'})
                  for index in schema(chosen, name, options)['indexes'] if index['name'] != '_id_']
        if models:
            destination[name].create_indexes(models)
        # Compare full BSON values, not just counts, before selecting this database.
        copied = documents(destination, name)
        if copied.keys() != merged.keys() or any(BSON.encode(copied[key]) != BSON.encode(doc) for key, doc in merged.items()):
            raise ValueError('Đối chiếu dữ liệu gộp không khớp: ' + name)
        total += len(merged)
        progress(f'Đã gộp và đối chiếu {name}: {len(merged)} dòng')
    return {'collections': len(names), 'rows': total}


def sync_cloud(request, progress, client_factory=MongoClient):
    source = target = None
    try:
        source = client_factory(request['sourceUri'], serverSelectionTimeoutMS=15000, socketTimeoutMS=120000)
        target = client_factory(request['targetUri'], serverSelectionTimeoutMS=15000, socketTimeoutMS=120000)
        source.admin.command('ping')
        target.admin.command('ping')
        src = source.get_default_database('XM').with_options(read_preference=ReadPreference.PRIMARY)
        current_target = target.get_default_database('XM').with_options(read_preference=ReadPreference.PRIMARY)
        base = current_target.name
        if src.name in ('admin', 'config', 'local') or base in ('admin', 'config', 'local'):
            raise ValueError('Không đồng bộ database hệ thống.')
        if request.get('command') == 'compareCloud':
            # Bound the entire comparison, not just each socket operation.
            from pymongo import timeout
            with timeout(180):
                return compare_databases(src, current_target, progress)
        expected_source = request.get('expectedSourceVersion')
        expected_target = request.get('expectedTargetVersion')
        if not expected_source or not expected_target:
            raise ValueError('Phải so sánh phiên bản trước khi đồng bộ.')
        source_version = version_database(src)
        target_version = version_database(current_target)
        if source_version['version'] != expected_source or target_version['version'] != expected_target:
            raise ValueError('Phiên bản database đã thay đổi sau khi xác nhận. So sánh lại trước khi đồng bộ.')
        policy = request.get('conflictPolicy', 'abort')
        if policy not in ('abort', 'source', 'target'):
            raise ValueError('Lựa chọn xử lý xung đột không hợp lệ.')
        name = snapshot_name(base)
        dst = target[name].with_options(read_preference=ReadPreference.PRIMARY, write_concern=WriteConcern(w='majority'))
        report = merge_snapshot(src, current_target, dst, policy, progress)
        migrate_database(dst)
        if version_database(src)['version'] != expected_source or version_database(current_target)['version'] != expected_target:
            raise ValueError('Dữ liệu đã thay đổi trong khi gộp. Bản cũ được giữ nguyên; hãy so sánh lại.')
        dst['_app_sync_meta'].insert_one({'_id': 'current', 'revision': max(source_version['revision'], target_version['revision']), 'parents': [expected_source, expected_target]})
        version = version_database(dst)
        dst['_app_sync_meta'].update_one({'_id': 'current'}, {'$set': {'parents': [expected_source, expected_target], 'conflictPolicy': policy}})
        dst['_app_sync_meta'].update_one({'_id': version['version']}, {'$set': {'parents': [expected_source, expected_target], 'conflictPolicy': policy}})
        # Both endpoints must select the verified merged data, not just the
        # destination. Create a second snapshot instead of altering either original.
        source_name = snapshot_name(src.name)
        mirror = source[source_name].with_options(read_preference=ReadPreference.PRIMARY, write_concern=WriteConcern(w='majority'))
        progress('Đang tạo bản dữ liệu khớp nhau ở phía còn lại…')
        copy_snapshot(dst, mirror, progress)
        with ExitStack() as snapshot_cleanup:
            guards = {}
            for db in (dst, mirror):
                guard = open_comparison_watch(db)
                guards[db.name] = guard
                if guard is not None: snapshot_cleanup.callback(guard.close)
            mirror_version = version_database(mirror)
            if mirror_version['version'] != version['version']:
                raise ValueError('Hai bản dữ liệu sau khi gộp không khớp. Giữ nguyên kết nối cũ.')
            if version_database(src)['version'] != expected_source or version_database(current_target)['version'] != expected_target or version_database(dst)['version'] != version['version']:
                raise ValueError('Dữ liệu thay đổi trong lúc đồng bộ. Hãy so sánh lại; kết nối cũ được giữ nguyên.')
            for guard in guards.values():
                if guard is not None and guard.try_next() is not None:
                    raise ValueError('Dữ liệu bản sao đã thay đổi. Giữ nguyên kết nối cũ và so sánh lại.')
            for db in (dst, mirror):
                record = {**version, 'database': db.name, 'parents': [expected_source, expected_target], 'conflictPolicy': policy}
                current_record = {'_id': 'current', **record}
                if guards.get(db.name) is not None:
                    current_record['comparisonToken'] = guards[db.name].resume_token
                db['_app_sync_meta'].replace_one({'_id': 'current'}, current_record, upsert=True)
                db['_app_sync_meta'].replace_one({'_id': version['version']}, {'_id': version['version'], **record}, upsert=True)
            report.update(database=name, mongoUri=snapshot_uri(request['targetUri'], name),
                          sourceMongoUri=snapshot_uri(request['sourceUri'], source_name), version=version)
            return report

    finally:
        if source is not None:
            source.close()
        if target is not None:
            target.close()
