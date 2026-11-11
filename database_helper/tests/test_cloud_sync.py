import sys
from pathlib import Path
import unittest
from unittest.mock import MagicMock
from urllib.parse import urlsplit, parse_qs

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

# mongomock is used only by tests, never bundled in the application.
try:
    import mongomock
except ImportError:
    mongomock = None


@unittest.skipIf(mongomock is None, 'Install mongomock to run MongoDB snapshot tests')
class CloudSnapshotTests(unittest.TestCase):
    def setUp(self):
        from cloud_sync import copy_snapshot
        self.copy = copy_snapshot
        client = mongomock.MongoClient()
        self.src = client.source
        self.dst = client.destination
        self.src.items.insert_many([{'_id': 1, 'code': 'A', 'qty': 3}, {'_id': 2, 'code': 'B', 'qty': 0}])
        self.src.items.create_index('code', unique=True)
        self.source = MagicMock()
        self.source.__getitem__.side_effect = self.src.__getitem__
        self.options = {'validator': {'qty': {'$gte': 0}}, 'validationLevel': 'strict'}
        self.source.list_collections.side_effect = lambda: [{'name': 'items', 'type': 'collection', 'options': self.options}]
        self.target = MagicMock()
        self.target.__getitem__.side_effect = self.dst.__getitem__
        self.target.list_collection_names.side_effect = self.dst.list_collection_names
        self.target.create_collection.side_effect = lambda name, **options: self.dst.create_collection(name)

    def test_copies_documents_indexes_and_validator_without_changing_source(self):
        report = self.copy(self.source, self.target, lambda _: None)
        self.assertEqual(report, {'collections': 1, 'rows': 2})
        self.assertEqual(list(self.src.items.find()), list(self.dst.items.find()))
        self.assertTrue(self.dst.items.index_information()['code_1']['unique'])
        self.target.create_collection.assert_called_once_with('items', **self.options)

    def test_never_overwrites_existing_destination(self):
        self.dst.keep.insert_one({'_id': 5})
        with self.assertRaisesRegex(ValueError, 'đã tồn tại'):
            self.copy(self.source, self.target, lambda _: None)
        self.assertEqual(self.dst.keep.count_documents({}), 1)
        self.target.create_collection.assert_not_called()

    def test_rejects_changes_during_copy(self):
        with self.assertRaisesRegex(ValueError, 'đã thay đổi'):
            self.copy(self.source, self.target, lambda _: self.src.items.update_one({'_id': 1}, {'$set': {'qty': 8}}))

    def test_rejects_views_and_empty_source(self):
        self.source.list_collections.return_value = []
        self.source.list_collections.side_effect = None
        with self.assertRaisesRegex(ValueError, 'chưa có dữ liệu'):
            self.copy(self.source, self.target, lambda _: None)
        self.source.list_collections.return_value = [{'name': 'v', 'type': 'view'}]
        with self.assertRaisesRegex(ValueError, 'view'):
            self.copy(self.source, self.target, lambda _: None)

    def test_uri_keeps_authentication_database(self):
        from cloud_sync import snapshot_uri
        for uri, expected in [('mongodb://u:p@local/XM', 'XM'), ('mongodb+srv://u:p@cluster/XM', 'admin'), ('mongodb://u:p@local/XM?authSource=users', 'users')]:
            result = urlsplit(snapshot_uri(uri, 'XM_sync_new'))
            self.assertEqual(result.path, '/XM_sync_new')
            self.assertEqual(parse_qs(result.query)['authSource'], [expected])


@unittest.skipIf(mongomock is None, 'Install mongomock to run MongoDB merge tests')
class MergeVersionTests(unittest.TestCase):
    def setUp(self):
        self.client = mongomock.MongoClient()
        self.left = self.client.left
        self.right = self.client.right
        self.result = self.client.result
        # mongomock does not implement list_collections; expose real mock collections.
        for db in (self.left, self.right, self.result):
            db.list_collections = lambda db=db: [{'name': name, 'type': 'collection', 'options': {}}
                                                 for name in db.list_collection_names()]
        self.left.items.insert_many([{'_id': 1, 'value': 'local'}, {'_id': 2, 'value': 'local-only'}])
        self.right.items.insert_many([{'_id': 1, 'value': 'cloud'}, {'_id': 3, 'value': 'cloud-only'}])

    def test_versions_track_content_and_preserve_history(self):
        from cloud_sync import version_database
        first = version_database(self.left)
        self.assertEqual(first['revision'], 1)
        self.assertEqual(first['version'], version_database(self.left)['version'])
        self.left.items.update_one({'_id': 1}, {'$set': {'value': 'changed'}})
        second = version_database(self.left)
        self.assertEqual(second['revision'], 2)
        self.assertNotEqual(first['version'], second['version'])
        self.assertEqual(self.left['_app_sync_meta'].count_documents({}), 3)
        self.assertEqual(second['rows'], 2)

    def test_comparison_reports_conflicts_and_records_only_on_one_side(self):
        from cloud_sync import compare_databases
        comparison = compare_databases(self.left, self.right)
        self.assertEqual(comparison['conflicts'], 1)
        self.assertEqual(comparison['sourceOnly'], 1)
        self.assertEqual(comparison['targetOnly'], 1)
        self.assertEqual(comparison['schemaConflicts'], 0)

    def test_merge_needs_explicit_policy_and_preserves_unique_records(self):
        from cloud_sync import merge_snapshot
        with self.assertRaisesRegex(ValueError, 'xung đột'):
            merge_snapshot(self.left, self.right, self.result, 'abort', lambda _: None)
        self.assertEqual(self.result.list_collection_names(), [])
        for policy, value in [('source', 'local'), ('target', 'cloud')]:
            self.client.drop_database('result')
            report = merge_snapshot(self.left, self.right, self.result, policy, lambda _: None)
            self.assertEqual(report['rows'], 3)
            self.assertEqual(self.result.items.find_one({'_id': 1})['value'], value)
            self.assertEqual(self.result.items.count_documents({}), 3)
        self.assertEqual(self.left.items.find_one({'_id': 1})['value'], 'local')
        self.assertEqual(self.right.items.find_one({'_id': 1})['value'], 'cloud')

    def test_stale_comparison_is_rejected(self):
        from cloud_sync import compare_databases, sync_cloud
        preview = compare_databases(self.left, self.right)
        self.left.items.insert_one({'_id': 8, 'value': 'changed after confirmation'})
        # Both endpoints use the same mock client, with their database specified by URI.
        class Endpoint:
            def __init__(self, db): self.db = db; self.admin = MagicMock()
            def get_default_database(self, _): return self.db
            def close(self): pass
        endpoints = iter([Endpoint(self.left), Endpoint(self.right)])
        with self.assertRaisesRegex(ValueError, 'đã thay đổi sau khi xác nhận'):
            sync_cloud({'command': 'syncCloud', 'sourceUri': 'mongodb://local/left', 'targetUri': 'mongodb://cloud/right',
                        'expectedSourceVersion': preview['sourceVersion']['version'],
                        'expectedTargetVersion': preview['targetVersion']['version'], 'conflictPolicy': 'source'},
                       lambda _: None, client_factory=lambda *a, **kw: next(endpoints))

    def test_successful_merge_records_parents_and_increases_revision(self):
        from cloud_sync import compare_databases, sync_cloud, version_database
        preview = compare_databases(self.left, self.right)
        client = self.client
        class Endpoint:
            def __init__(self, db): self.db = db; self.admin = MagicMock()
            def get_default_database(self, _): return self.db
            def __getitem__(self, name):
                db = client[name]
                db.with_options = lambda **kwargs: db
                db.list_collections = lambda: [{'name': n, 'type': 'collection', 'options': {}} for n in db.list_collection_names()]
                return db
            def close(self): pass
        endpoints = iter([Endpoint(self.left), Endpoint(self.right)])
        result = sync_cloud({'command': 'syncCloud', 'sourceUri': 'mongodb://local/left', 'targetUri': 'mongodb://cloud/right',
                             'expectedSourceVersion': preview['sourceVersion']['version'],
                             'expectedTargetVersion': preview['targetVersion']['version'], 'conflictPolicy': 'source'},
                            lambda _: None, client_factory=lambda *a, **kw: next(endpoints))
        self.assertEqual(result['rows'], 3)
        self.assertEqual(result['version']['revision'], 2)
        db = client[result['database']]
        version_database(db)
        meta = db['_app_sync_meta'].find_one({'_id': 'current'})
        self.assertEqual(meta['parents'], [preview['sourceVersion']['version'], preview['targetVersion']['version']])
        self.assertEqual(meta['conflictPolicy'], 'source')
        self.assertEqual(self.right.items.count_documents({}), 2)
        mirror = client[urlsplit(result['sourceMongoUri']).path.lstrip('/')]
        left_version = version_database(mirror)
        right_version = version_database(db)
        self.assertEqual(left_version['version'], right_version['version'])
        self.assertEqual(left_version['revision'], right_version['revision'])
        self.assertEqual(list(mirror.items.find().sort('_id')), list(db.items.find().sort('_id')))
        self.assertEqual(self.left.items.count_documents({}), 2)

    def test_allocation_counter_never_moves_backwards(self):
        from cloud_sync import merge_snapshot
        self.left['_app_counters'].insert_one({'_id': 'CamDo', 'value': 20})
        self.right['_app_counters'].insert_one({'_id': 'CamDo', 'value': 30})
        merge_snapshot(self.left, self.right, self.result, 'source', lambda _: None)
        self.assertEqual(self.result['_app_counters'].find_one({'_id': 'CamDo'})['value'], 30)

    def test_schema_conflicts_require_selection_and_keep_chosen_indexes(self):
        from cloud_sync import compare_databases, merge_snapshot
        self.right.items.create_index('value', name='cloud_value')
        self.assertEqual(compare_databases(self.left, self.right)['schemaConflicts'], 1)
        with self.assertRaisesRegex(ValueError, 'Cấu trúc'):
            merge_snapshot(self.left, self.right, self.result, 'abort', lambda _: None)
        merge_snapshot(self.left, self.right, self.result, 'target', lambda _: None)
        self.assertIn('cloud_value', self.result.items.index_information())

    def test_snapshot_names_fit_atlas_shared_limit(self):
        from cloud_sync import snapshot_name
        for base in ('XM', 'X' * 63, 'Dữ_liệu_' * 12, 'XM_sync_old'):
            name = snapshot_name(base)
            self.assertLessEqual(len(name.encode('utf-8')), 38)
            self.assertNotEqual(name, snapshot_name(base))

    def test_standalone_comparison_scans_each_collection_only_twice(self):
        from cloud_sync import compare_databases
        from unittest.mock import patch
        with patch.object(self.left.items, 'find', wraps=self.left.items.find) as left_reads, patch.object(self.right.items, 'find', wraps=self.right.items.find) as right_reads:
            compare_databases(self.left, self.right)
            self.assertEqual(left_reads.call_count, 2)
            self.assertEqual(right_reads.call_count, 2)

    def test_verification_detects_edits_with_unchanged_document_count(self):
        from cloud_sync import compare_databases
        def progress(message):
            if message.startswith('Đang xác nhận'):
                self.right.items.update_one({'_id': 1}, {'$set': {'value': 'edited during comparison'}})
        with self.assertRaisesRegex(ValueError, 'đã thay đổi'):
            compare_databases(self.left, self.right, progress)

    def test_matching_cached_versions_skip_document_reads_when_stream_confirms_no_changes(self):
        from cloud_sync import compare_databases, version_database
        from unittest.mock import patch
        self.right.items.replace_one({'_id': 1}, {'_id': 1, 'value': 'local'})
        self.right.items.delete_one({'_id': 3})
        self.right.items.insert_one({'_id': 2, 'value': 'local-only'})
        version_database(self.left)
        version_database(self.right)
        for db in (self.left, self.right):
            db['_app_sync_meta'].update_one({'_id': 'current'}, {'$set': {'comparisonToken': {'_data': 'test'}}})
        def watch(*args):
            stream = MagicMock()
            stream.try_next.return_value = None
            stream.resume_token = {'_data': 'new-position'}
            return stream
        with patch('cloud_sync.open_comparison_watch', side_effect=watch), patch.object(self.left.items, 'find', wraps=self.left.items.find) as reads:
            report = compare_databases(self.left, self.right)
            self.assertEqual(report['identical'], 2)
            self.assertEqual(report['conflicts'], 0)
            self.assertEqual(reads.call_count, 0)

    def test_worker_threads_preserve_timeout_context(self):
        from cloud_sync import compare_databases, schema
        from contextvars import ContextVar
        from unittest.mock import patch
        marker = ContextVar('comparison-test', default=False)
        token = marker.set(True)
        try:
            def checked_schema(*args):
                self.assertTrue(marker.get())
                return schema(*args)
            with patch('cloud_sync.schema', side_effect=checked_schema):
                compare_databases(self.left, self.right)
        finally:
            marker.reset(token)

    def test_changed_stream_invalidates_cached_version_and_reads_updated_records(self):
        from cloud_sync import compare_databases, version_database
        from unittest.mock import patch
        version_database(self.left)
        version_database(self.right)
        for db in (self.left, self.right):
            db['_app_sync_meta'].update_one({'_id': 'current'}, {'$set': {'comparisonToken': {'_data': 'old'}}})
        self.left.items.update_one({'_id': 1}, {'$set': {'value': 'new edit'}})
        def watch(db, token=None):
            stream = MagicMock()
            stream.resume_token = {'_data': 'fresh'}
            stream.try_next.return_value = {'operationType': 'update'} if token is not None else None
            return stream
        with patch('cloud_sync.open_comparison_watch', side_effect=watch):
            report = compare_databases(self.left, self.right)
        self.assertEqual(report['conflicts'], 1)
        self.assertEqual(report['sourceOnly'], 1)
        self.assertEqual(report['targetOnly'], 1)

    def test_changes_during_scan_abort_stream_based_comparison(self):
        from cloud_sync import compare_databases
        from unittest.mock import patch
        def watch(*args):
            stream = MagicMock()
            stream.resume_token = {'_data': 'fresh'}
            stream.try_next.return_value = {'operationType': 'createIndexes'}
            return stream
        with patch('cloud_sync.open_comparison_watch', side_effect=watch):
            with self.assertRaisesRegex(ValueError, 'đã thay đổi'):
                compare_databases(self.left, self.right)
