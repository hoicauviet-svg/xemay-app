"""Verified MongoDB snapshots; never overwrite an existing database."""
from customer_addresses import migrate_database
import hashlib
import re
import time
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

_COPY_BATCH_SIZE = 1000


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


def create_indexes_safely(collection, models):
    """Build copied indexes serially; Atlas can reject concurrent builds under FD pressure."""
    for model in models:
        for attempt in range(5):
            try:
                collection.create_indexes([model])
                break
            except OperationFailure as error:
                too_many_files = (
                    error.code == 264
                    or 'too many open files' in str(error).lower()
                )
                if not too_many_files or attempt == 4:
                    raise
                time.sleep(2 ** attempt)


def collection_specs(db):
    specs = {}
    for spec in db.list_collections():
        if spec['name'].startswith('system.') or spec['name'] in {
            '_app_sync_meta', '_sync_changes', '_sync_state',
        }:
            continue
        if spec.get('type', 'collection') != 'collection':
            raise ValueError('Chưa hỗ trợ đồng bộ view hoặc time series. Dữ liệu gốc được giữ nguyên.')
        specs[spec['name']] = spec.get('options', {})
    return specs


def copy_snapshot(source, target, progress, verify=True):
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
        for document in source[name].find().sort('_id', 1).batch_size(_COPY_BATCH_SIZE):
            if verify:
                digest.update(BSON.encode(document))
            batch.append(document)
            count += 1
            if len(batch) >= _COPY_BATCH_SIZE:
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
            create_indexes_safely(target[name], models)
        if verify:
            fingerprints[name] = (count, digest.hexdigest())
        if verify and fingerprint(target[name]) != fingerprints[name]:
            raise ValueError('Đối chiếu dữ liệu không khớp: ' + name)
        total += count
        progress(f'Đã sao chép và đối chiếu {name}: {count} dòng')
    # A source edited during copying is not accepted as a complete backup.
    if verify:
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


def superset_database(source, target, source_only, target_only, conflicts, schema_conflicts):
    """Return the already-complete side when the compared data differs one way."""
    if None in (source_only, target_only, conflicts, schema_conflicts):
        return None
    if conflicts or schema_conflicts or (source_only and target_only):
        return None
    preferred = source if target_only == 0 else target
    source_specs, target_specs = collection_specs(source), collection_specs(target)
    if source_specs.keys() != target_specs.keys():
        return None
    if any(schema(source, name, source_specs[name]) != schema(target, name, target_specs[name])
           for name in source_specs):
        return None
    return preferred


def key_for(document):
    return bytes(BSON.encode({'_id': document['_id']}))


def documents(db, name):
    return {key_for(doc): doc for doc in db[name].find().sort('_id', 1).batch_size(500)}


def version_from_collection_hashes(collections):
    digest = hashlib.sha256()
    for name in sorted(collections):
        item = collections[name]
        digest.update(BSON.encode({'name': name, 'content': item['content'], 'schema': item['schema']}))
    return {
        'version': digest.hexdigest(),
        'rows': sum(item['count'] for item in collections.values()),
        'collections': len(collections),
    }


def commit_history(db):
    return list(db['_app_sync_meta'].find({'_id': {'$regex': '^commit:'}}))


def journal_ready(db):
    state = db['_sync_state'].find_one({'_id': 'journal'}) or {}
    return (
        state.get('initialized') is True
        and not state.get('pendingOperations')
        and state.get('needsFullScan') is not True
    )


def pending_changes(db):
    return list(db['_sync_changes'].find({
        'eventType': 'change', 'synced': {'$ne': True}, 'status': 'ready',
    }).sort([('generation', 1), ('order', 1)]))


def journal_document_key(event):
    return BSON.encode({'collection': event['collection'], '_id': event['documentId']})


def journal_after_equal(left, right):
    left_after, right_after = left.get('after'), right.get('after')
    if left['collection'] == '_app_counters' and left_after is not None and right_after is not None:
        if isinstance(left_after.get('value'), (int, float)) and isinstance(right_after.get('value'), (int, float)):
            return True
    if left_after is None or right_after is None:
        return left_after is None and right_after is None
    return BSON.encode(left_after) == BSON.encode(right_after)


def endpoint_id(uri):
    parts = urlsplit(uri)
    database = parts.path.strip('/')
    endpoint = f'{parts.scheme}://{parts.hostname or parts.netloc}:{parts.port or ""}/{database}'
    return hashlib.sha256(endpoint.encode()).hexdigest()[:24]


def journal_changes_by_document(events):
    changes = {}
    for event in events:
        key = journal_document_key(event)
        current = changes.get(key)
        if current is None:
            changes[key] = {'first': event, 'last': event}
        else:
            current['last'] = event
    return changes


def journal_version(meta, events):
    parent = (meta or {}).get('version', '')
    if not events:
        return parent
    digest = hashlib.sha256()
    digest.update(BSON.encode({'parent': parent}))
    for event in events:
        digest.update(BSON.encode({'eventId': event['_id']}))
    return digest.hexdigest()


def journal_rows(meta, changes):
    rows = (meta or {}).get('rows', 0)
    for item in changes.values():
        before = item['first'].get('before')
        after = item['last'].get('after')
        rows += int(after is not None) - int(before is not None)
    return rows


def compare_journals(source, target):
    left_meta = source['_app_sync_meta'].find_one({'_id': 'current'}) or {}
    right_meta = target['_app_sync_meta'].find_one({'_id': 'current'}) or {}
    left_events, right_events = pending_changes(source), pending_changes(target)
    left_changes = journal_changes_by_document(left_events)
    right_changes = journal_changes_by_document(right_events)
    report = {
        'sourceOnly': 0,
        'targetOnly': 0,
        'conflicts': 0,
        'identical': 0,
        'schemaConflicts': 0,
    }
    for key in left_changes.keys() | right_changes.keys():
        left = left_changes.get(key)
        right = right_changes.get(key)
        if left is None:
            report['targetOnly'] += 1
        elif right is None:
            report['sourceOnly'] += 1
        elif journal_after_equal(left['last'], right['last']):
            report['identical'] += 1
        else:
            report['conflicts'] += 1
    left_state = source['_sync_state'].find_one({'_id': 'journal'}) or {}
    right_state = target['_sync_state'].find_one({'_id': 'journal'}) or {}
    return {
        **report,
        'sourceVersion': {
            'version': journal_version(left_meta, left_events),
            'revision': left_meta.get('revision', 0),
            'observedAt': left_meta.get('observedAt', datetime.now(timezone.utc).isoformat()),
            'rows': journal_rows(left_meta, left_changes),
            'collections': left_meta.get('collections', 0),
        },
        'targetVersion': {
            'version': journal_version(right_meta, right_events),
            'revision': right_meta.get('revision', 0),
            'observedAt': right_meta.get('observedAt', datetime.now(timezone.utc).isoformat()),
            'rows': journal_rows(right_meta, right_changes),
            'collections': right_meta.get('collections', 0),
        },
        '_journal': {
            'sourceGeneration': left_state.get('generation', 0),
            'targetGeneration': right_state.get('generation', 0),
        },
    }


def sync_from_journal(request, source, target, progress):
    """Apply journaled document changes in place; no business collection scan/copy."""
    preview = compare_journals(source, target)
    if (preview['sourceVersion']['version'] != request.get('expectedSourceVersion') or
            preview['targetVersion']['version'] != request.get('expectedTargetVersion')):
        raise ValueError('Nhật ký thay đổi đã cập nhật sau khi so sánh. Hãy so sánh lại.')
    source_events, target_events = pending_changes(source), pending_changes(target)
    if not source_events and not target_events:
        source_meta = source['_app_sync_meta'].find_one({'_id': 'current'}) or {}
        target_meta = target['_app_sync_meta'].find_one({'_id': 'current'}) or {}
        if source_meta.get('version') != target_meta.get('version'):
            return None
        state = source['_sync_state'].find_one({'_id': 'journal'}) or {}
        current_version = {
            'version': source_meta.get('version', ''),
            'revision': source_meta.get('revision', 0),
            'observedAt': source_meta.get('observedAt', datetime.now(timezone.utc).isoformat()),
            'rows': source_meta.get('rows', 0),
            'collections': source_meta.get('collections', 0),
        }
        return {
            'database': target.name,
            'mongoUri': request['targetUri'],
            'sourceMongoUri': request['sourceUri'],
            'rows': current_version['rows'],
            'collections': current_version['collections'],
            'version': current_version,
            'commit': {'commitId': state.get('lastCommitId')},
            'changes': {'sourceOnly': 0, 'targetOnly': 0, 'conflicts': 0, 'identical': 0, 'collections': {}},
            'noChanges': True,
            'incremental': True,
        }

    policy = request.get('conflictPolicy', 'abort')
    if policy not in ('abort', 'source', 'target'):
        raise ValueError('Lựa chọn xử lý xung đột không hợp lệ.')
    if preview['conflicts'] and policy == 'abort':
        raise ValueError('Có bản ghi xung đột. Chọn bên ưu tiên hoặc hủy.')

    source_changes = journal_changes_by_document(source_events)
    target_changes = journal_changes_by_document(target_events)
    source_meta = source['_app_sync_meta'].find_one({'_id': 'current'}) or {}
    target_meta = target['_app_sync_meta'].find_one({'_id': 'current'}) or {}
    source_state = source['_sync_state'].find_one({'_id': 'journal'}) or {}
    target_state = target['_sync_state'].find_one({'_id': 'journal'}) or {}
    source_endpoint = endpoint_id(request['sourceUri'])
    target_endpoint = endpoint_id(request['targetUri'])
    base_version = source_meta.get('version', '')
    event_ids = sorted(
        (event['_id'] for event in [*source_events, *target_events]),
        key=lambda value: value.binary,
    )
    version_digest = hashlib.sha256(BSON.encode({
        'parent': base_version,
        'events': event_ids,
        'conflictPolicy': policy,
    })).hexdigest()
    now = datetime.now(timezone.utc).isoformat()
    parent_ids = []
    saved_history = {
        item['_id']: item
        for db in (source, target)
        for item in commit_history(db)
    }
    for parent_version in (source_meta.get('version'), target_meta.get('version')):
        parent_commit = max(
            (item for item in saved_history.values()
             if item.get('version') == parent_version and item.get('commitId')),
            key=lambda item: item.get('createdAt', ''),
            default=None,
        )
        parent_ids.append(parent_commit['commitId'] if parent_commit else parent_version)
    parent_ids = list(dict.fromkeys(item for item in parent_ids if item))
    conflict_policy = policy
    message = str(request.get('commitMessage') or '').strip()[:120]
    commit_id = hashlib.sha256(BSON.encode({
        'version': version_digest,
        'parents': parent_ids,
        'message': message,
        'createdAt': now,
    })).hexdigest()

    rows = source_meta.get('rows', 0)
    changed_keys = source_changes.keys() | target_changes.keys()
    delta_records = []
    per_collection = {}
    progress(f"Đang áp dụng {len(changed_keys):,} bản ghi từ nhật ký thay đổi…")
    for key in changed_keys:
        left_change = source_changes.get(key)
        right_change = target_changes.get(key)
        left_event = left_change['last'] if left_change else None
        right_event = right_change['last'] if right_change else None
        collection_name = (left_event or right_event)['collection']
        document_id = (left_event or right_event)['documentId']
        source_collection = source[collection_name]
        target_collection = target[collection_name]
        source_before_now = source_collection.find_one({'_id': document_id})
        target_before_now = target_collection.find_one({'_id': document_id})

        if left_event is not None and right_event is not None:
            if collection_name == '_app_counters':
                left_after, right_after = left_event.get('after'), right_event.get('after')
                if left_after is not None and right_after is not None and isinstance(left_after.get('value'), (int, float)) and isinstance(right_after.get('value'), (int, float)):
                    desired = {**left_after, 'value': max(left_after['value'], right_after['value'])}
                elif journal_after_equal(left_event, right_event):
                    desired = left_after
                else:
                    desired = left_after if policy == 'source' else right_after
            elif journal_after_equal(left_event, right_event):
                desired = left_event.get('after')
            else:
                desired = left_event.get('after') if policy == 'source' else right_event.get('after')
        else:
            desired = (left_event or right_event).get('after')

        if desired is None:
            source_collection.delete_one({'_id': document_id})
            target_collection.delete_one({'_id': document_id})
        else:
            source_collection.replace_one({'_id': document_id}, desired, upsert=True)
            target_collection.replace_one({'_id': document_id}, desired, upsert=True)

        if left_change is not None:
            base_document = left_change['first'].get('before')
        elif right_change is not None:
            base_document = right_change['first'].get('before')
        else:
            base_document = source_before_now
        rows += int(desired is not None) - int(base_document is not None)
        table_stats = per_collection.setdefault(collection_name, {
            'sourceOnly': 0, 'targetOnly': 0, 'conflicts': 0, 'identical': 0,
        })
        if left_change is None:
            table_stats['targetOnly'] += 1
        elif right_change is None:
            table_stats['sourceOnly'] += 1
        elif journal_after_equal(left_event, right_event):
            table_stats['identical'] += 1
        else:
            table_stats['conflicts'] += 1
        delta_records.append({
            '_id': ObjectId(),
            'eventType': 'commitDelta',
            'commitId': commit_id,
            'collection': collection_name,
            'documentId': document_id,
            'beforeByEndpoint': {
                source_endpoint: left_change['first'].get('before') if left_change else source_before_now,
                target_endpoint: right_change['first'].get('before') if right_change else target_before_now,
            },
            'afterByEndpoint': {
                source_endpoint: desired,
                target_endpoint: desired,
            },
            'changedAt': now,
        })

    # Do not acknowledge a moving journal. Reapplying these idempotent changes
    # is safe; a fresh comparison will include any writes that arrived meanwhile.
    for db, initial_events, initial_state in (
        (source, source_events, source_state),
        (target, target_events, target_state),
    ):
        current_state = db['_sync_state'].find_one({'_id': 'journal'}) or {}
        current_events = pending_changes(db)
        if current_state.get('pendingOperations') or current_state.get('generation', 0) != initial_state.get('generation', 0):
            raise ValueError('Dữ liệu vừa thay đổi trong lúc đồng bộ. Hãy so sánh lại.')
        if {event['_id'] for event in current_events} != {event['_id'] for event in initial_events}:
            raise ValueError('Nhật ký vừa được cập nhật. Hãy so sánh lại.')

    changes = {
        'sourceOnly': preview['sourceOnly'],
        'targetOnly': preview['targetOnly'],
        'conflicts': preview['conflicts'],
        'identical': preview['identical'],
        'collections': per_collection,
    }
    commit = {
        '_id': 'commit:' + commit_id,
        'commitId': commit_id,
        'version': version_digest,
        'revision': max(source_meta.get('revision', 0), target_meta.get('revision', 0)) + 1,
        'createdAt': now,
        'message': message,
        'conflictPolicy': conflict_policy,
        'parents': parent_ids,
        'sourceDatabase': source.name,
        'targetDatabase': target.name,
        'sourceEndpoint': source_endpoint,
        'targetEndpoint': target_endpoint,
        'changes': changes,
        'incremental': True,
    }
    all_events = {event['_id']: event for event in [*source_events, *target_events]}
    for event in all_events.values():
        committed = {**event, 'synced': True, 'commitId': commit_id}
        for db in (source, target):
            db['_sync_changes'].replace_one({'_id': event['_id']}, committed, upsert=True)
    for db in (source, target):
        for delta in delta_records:
            db['_sync_changes'].replace_one({'_id': delta['_id']}, delta, upsert=True)
        record = {
            '_id': 'current',
            'version': version_digest,
            'revision': commit['revision'],
            'observedAt': now,
            'database': db.name,
            'rows': rows,
            'collections': source_meta.get('collections', 0),
            'parents': parent_ids,
            'conflictPolicy': policy,
        }
        db['_app_sync_meta'].replace_one({'_id': 'current'}, record, upsert=True)
        db['_app_sync_meta'].replace_one({'_id': commit['_id']}, commit, upsert=True)
        db['_sync_state'].update_one(
            {'_id': 'journal'},
            {'$set': {'initialized': True, 'lastCommitId': commit_id}},
            upsert=True,
        )
    new_version = {
        'version': commit['version'],
        'revision': commit['revision'],
        'observedAt': now,
    }
    new_version.update(rows=rows, collections=source_meta.get('collections', 0))
    return {
        'database': target.name,
        'mongoUri': request['targetUri'],
        'sourceMongoUri': request['sourceUri'],
        'rows': rows,
        'collections': source_meta.get('collections', 0),
        'version': new_version,
        'commit': commit,
        'changes': changes,
        'incremental': True,
    }
def persist_commit_history(db, entries):
    for entry in entries:
        db['_app_sync_meta'].replace_one({'_id': entry['_id']}, entry, upsert=True)


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
        # Standalone servers cannot use cached metadata safely, so read a fresh
        # preview; sync_cloud validates the expected version before switching.
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
            # A standalone local MongoDB has no change stream. Do not read the
            # whole database twice just to render a preview; sync_cloud checks
            # the expected version again before switching either active URI.
            announce(f'{label}: đã hoàn tất lượt quét. Phiên bản sẽ được kiểm tra lại khi đồng bộ.')
            return scan
        # Stream cursor operations are serialized after the scan workers finish.
        # Change-stream checks run after the scan workers finish.
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
    changes = {
        'sourceOnly': 0,
        'targetOnly': 0,
        'conflicts': 0,
        'identical': 0,
        'collections': {},
    }
    source_hashes, target_hashes = {}, {}
    for name in names:
        left = documents(source, name) if name in left_specs else {}
        right = documents(target, name) if name in right_specs else {}
        if name in left_specs:
            digest = hashlib.sha256()
            for document in left.values():
                digest.update(BSON.encode(document))
            source_hashes[name] = {
                'count': len(left),
                'content': digest.hexdigest(),
                'schema': schema(source, name, left_specs[name]),
            }
        if name in right_specs:
            digest = hashlib.sha256()
            for document in right.values():
                digest.update(BSON.encode(document))
            target_hashes[name] = {
                'count': len(right),
                'content': digest.hexdigest(),
                'schema': schema(target, name, right_specs[name]),
            }
        source_only = len(left.keys() - right.keys())
        target_only = len(right.keys() - left.keys())
        conflicts = sum(
            BSON.encode(left[key]) != BSON.encode(right[key])
            for key in left.keys() & right.keys()
        )
        identical = len(left.keys() & right.keys()) - conflicts
        changes['sourceOnly'] += source_only
        changes['targetOnly'] += target_only
        changes['conflicts'] += conflicts
        changes['identical'] += identical
        changes['collections'][name] = {
            'sourceOnly': source_only,
            'targetOnly': target_only,
            'conflicts': conflicts,
            'identical': identical,
        }
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
    return {
        'collections': len(names),
        'rows': total,
        'changes': changes,
        '_sourceVersion': version_from_collection_hashes(source_hashes),
        '_targetVersion': version_from_collection_hashes(target_hashes),
    }


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
                if journal_ready(src) and journal_ready(current_target):
                    progress('Đang đối chiếu nhật ký thay đổi…')
                    result = compare_journals(src, current_target)
                    result.pop('_journal', None)
                    progress('Đã đối chiếu nhật ký; không quét các bảng không thay đổi.')
                    return result
                return compare_databases(src, current_target, progress)
        expected_source = request.get('expectedSourceVersion')
        expected_target = request.get('expectedTargetVersion')
        if not expected_source or not expected_target:
            raise ValueError('Phải so sánh phiên bản trước khi đồng bộ.')
        if journal_ready(src) and journal_ready(current_target):
            result = sync_from_journal(request, src, current_target, progress)
            if result is not None:
                return result
        source_record = src['_app_sync_meta'].find_one({'_id': 'current'}) or {}
        target_record = current_target['_app_sync_meta'].find_one({'_id': 'current'}) or {}
        if source_record.get('version') != expected_source or target_record.get('version') != expected_target:
            raise ValueError('Phiên bản database đã thay đổi sau khi xác nhận. So sánh lại trước khi đồng bộ.')
        source_revision = source_record.get('revision', 0)
        target_revision = target_record.get('revision', 0)
        policy = request.get('conflictPolicy', 'abort')
        if policy not in ('abort', 'source', 'target'):
            raise ValueError('Lựa chọn xử lý xung đột không hợp lệ.')
        name = snapshot_name(base)
        dst = target[name].with_options(read_preference=ReadPreference.PRIMARY, write_concern=WriteConcern(w='majority'))
        saved_history = {
            entry['_id']: entry
            for db in (src, current_target)
            for entry in commit_history(db)
        }
        source_name = snapshot_name(src.name)
        mirror = source[source_name].with_options(read_preference=ReadPreference.PRIMARY, write_concern=WriteConcern(w='majority'))
        base = superset_database(
            src,
            current_target,
            request.get('expectedSourceOnly'),
            request.get('expectedTargetOnly'),
            request.get('expectedConflicts'),
            request.get('expectedSchemaConflicts'),
        )
        revision = max(source_revision, target_revision)
        if base is not None:
            progress('Chênh lệch một chiều: tạo snapshot từ phía đã đủ dữ liệu, bỏ bước gộp từng bản ghi.')
            for snapshot in (dst, mirror):
                copy_snapshot(base, snapshot, progress, verify=False)
                migrate_database(snapshot)
                snapshot['_app_sync_meta'].insert_one({
                    '_id': 'current', 'revision': revision,
                    'parents': [expected_source, expected_target],
                    'conflictPolicy': policy,
                })
            changes = {
                'sourceOnly': request['expectedSourceOnly'],
                'targetOnly': request['expectedTargetOnly'],
                'conflicts': request['expectedConflicts'],
                'identical': max(
                    0,
                    min(source_record.get('rows', 0), target_record.get('rows', 0))
                    - request['expectedConflicts'],
                ),
                'collections': {},
            }
            report = {'changes': changes}
        else:
            progress(
                'Cần gộp đầy đủ để giữ đúng dữ liệu: '
                f"chỉ nguồn={request.get('expectedSourceOnly')}, "
                f"chỉ đích={request.get('expectedTargetOnly')}, "
                f"xung đột={request.get('expectedConflicts')}, "
                f"khác cấu trúc={request.get('expectedSchemaConflicts')}."
            )
            report = merge_snapshot(src, current_target, dst, policy, progress)
            measured_source = report.pop('_sourceVersion')
            measured_target = report.pop('_targetVersion')
            if measured_source['version'] != expected_source or measured_target['version'] != expected_target:
                raise ValueError('Dữ liệu đã thay đổi sau khi xác nhận. So sánh lại trước khi đồng bộ.')
            revision = max(measured_source.get('revision', source_revision), measured_target.get('revision', target_revision))
            migrate_database(dst)
            dst['_app_sync_meta'].insert_one({
                '_id': 'current', 'revision': revision,
                'parents': [expected_source, expected_target],
                'conflictPolicy': policy,
            })
            progress('Đang tạo snapshot phía còn lại…')
            copy_snapshot(dst, mirror, progress, verify=False)
        with ExitStack() as snapshot_cleanup:
            guards = {}
            for db in (dst, mirror):
                guard = open_comparison_watch(db)
                guards[db.name] = guard
                if guard is not None: snapshot_cleanup.callback(guard.close)
            version = version_database(dst)
            mirror_version = version_database(mirror)
            if mirror_version['version'] != version['version']:
                raise ValueError('Hai bản snapshot sau đồng bộ không khớp. Giữ nguyên kết nối cũ.')
            if version_database(src)['version'] != expected_source or version_database(current_target)['version'] != expected_target:
                raise ValueError('Dữ liệu thay đổi trong lúc đồng bộ. Hãy so sánh lại; kết nối cũ được giữ nguyên.')
            for db in (dst, mirror):
                db['_app_sync_meta'].update_one(
                    {'_id': 'current'},
                    {'$set': {'parents': [expected_source, expected_target], 'conflictPolicy': policy}},
                )
                db['_app_sync_meta'].update_one(
                    {'_id': version['version']},
                    {'$set': {'parents': [expected_source, expected_target], 'conflictPolicy': policy}},
                )
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
            commit = {
                '_id': '',
                'version': version['version'],
                'revision': version['revision'],
                'createdAt': datetime.now(timezone.utc).isoformat(),
                'message': str(request.get('commitMessage') or '').strip()[:120],
                'conflictPolicy': policy,
                'sourceDatabase': mirror.name,
                'targetDatabase': dst.name,
                'changes': report.get('changes', {}),
            }
            parent_commits = []
            for parent_version in (expected_source, expected_target):
                parent_commit = max(
                    (item for item in saved_history.values()
                     if item.get('version') == parent_version and item.get('commitId')),
                    key=lambda item: item.get('createdAt', ''),
                    default=None,
                )
                parent_commits.append(
                    parent_commit['commitId'] if parent_commit is not None else parent_version
                )
            commit['parents'] = list(dict.fromkeys(parent_commits))
            commit['commitId'] = hashlib.sha256(BSON.encode({
                'tree': commit['version'],
                'parents': commit['parents'],
                'message': commit['message'],
                'createdAt': commit['createdAt'],
            })).hexdigest()
            commit['_id'] = 'commit:' + commit['commitId']
            history = sorted(
                [*saved_history.values(), commit],
                key=lambda item: item.get('createdAt', ''),
            )
            for db in (dst, mirror):
                persist_commit_history(db, history)
                db['_sync_state'].replace_one(
                    {'_id': 'journal'},
                    {
                        '_id': 'journal',
                        'initialized': True,
                        'generation': 0,
                        'pendingOperations': [],
                        'needsFullScan': False,
                        'lastCommitId': commit['commitId'],
                    },
                    upsert=True,
                )
            report.update(database=name, mongoUri=snapshot_uri(request['targetUri'], name),
                          sourceMongoUri=snapshot_uri(request['sourceUri'], source_name),
                          version=version, commit=commit,
                          changes=report.get('changes', {}))
            report.setdefault('rows', version['rows'])
            report.setdefault('collections', version['collections'])
            return report

    finally:
        if source is not None:
            source.close()
        if target is not None:
            target.close()
