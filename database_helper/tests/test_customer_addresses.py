import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mongomock
from customer_addresses import flatten_rows, migrate_database


class CustomerAddressesTest(unittest.TestCase):
    def setUp(self):
        self.db = mongomock.MongoClient().test
        self.db.Xa.insert_one({'_id': 'xa7', 'IdXa': 7, 'TenXa': 'Mậu A, Văn Yên, Yên Bái'})
        self.db.KhachHang.insert_many([
            {'_id': 'a', 'IdKH': 1, 'IdXa': 7, 'DiaChiChiTiet': 'Tổ 3'},
            {'_id': 'b', 'IdKH': 2, 'IdXa': 7, 'DiaChiChiTiet': 'Tổ 4, Mậu A, Văn Yên, Yên Bái'},
            {'_id': 'c', 'IdKH': 3, 'IdXa': 7},
            {'_id': 'd', 'IdKH': 4, 'DiaChiChiTiet': 'Địa chỉ đầy đủ'},
        ])

    def test_migrate_preserves_directory_and_is_idempotent(self):
        migrate_database(self.db)
        self.assertNotIn('Xa', self.db.list_collection_names())
        self.assertEqual(self.db.KhachHang.find_one({'_id': 'a'})['DiaChiChiTiet'], 'Tổ 3, Mậu A, Văn Yên, Yên Bái')
        self.assertEqual(self.db.KhachHang.find_one({'_id': 'b'})['DiaChiChiTiet'], 'Tổ 4, Mậu A, Văn Yên, Yên Bái')
        self.assertEqual(self.db.KhachHang.find_one({'_id': 'c'})['DiaChiChiTiet'], 'Mậu A, Văn Yên, Yên Bái')
        self.assertEqual(self.db.KhachHang.find_one({'_id': 'd'})['DiaChiChiTiet'], 'Địa chỉ đầy đủ')
        self.assertEqual(self.db.KhachHang.count_documents({'IdXa': {'$exists': True}}), 0)
        before = list(self.db.KhachHang.find())
        migrate_database(self.db)
        self.assertEqual(before, list(self.db.KhachHang.find()))
        self.assertEqual(self.db['_app_address_archive'].count_documents({}), 1)

    def test_missing_locality_keeps_every_customer_and_directory_unchanged(self):
        self.db.KhachHang.insert_one({'_id': 'bad', 'IdXa': 999})
        before = list(self.db.KhachHang.find())
        with self.assertRaises(ValueError):
            migrate_database(self.db)
        self.assertEqual(before, list(self.db.KhachHang.find()))
        self.assertIn('Xa', self.db.list_collection_names())

    def test_sql_rows_flatten_without_mutating_original(self):
        raw = {'Xa': {'xa7': self.db.Xa.find_one()}, 'KhachHang': {r['_id']: r for r in self.db.KhachHang.find()}}
        rows = copy.deepcopy(raw)
        flatten_rows(rows)
        self.assertNotIn('Xa', rows)
        self.assertIn('Xa', raw)
        self.assertIn('IdXa', raw['KhachHang']['a'])
        self.assertNotIn('IdXa', rows['KhachHang']['a'])


if __name__ == '__main__':
    unittest.main()
