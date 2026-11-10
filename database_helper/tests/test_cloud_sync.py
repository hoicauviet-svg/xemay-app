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
