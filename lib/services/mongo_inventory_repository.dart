import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../core/config/database_config.dart';
import 'cost_delete_repair.dart';
import '../models/inventory/inventory_models.dart';
import '../models/repositories/inventory_repository.dart';

/// Local desktop repository. Reads only until editing workflows are implemented.
class MongoInventoryRepository implements InventoryRepository {
  MongoInventoryRepository({String? uri})
    : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  Future<void>? _pendingConnection;

  @override
  Future<void> connect() => _pendingConnection ??= _open().whenComplete(() {
    _pendingConnection = null;
  });

  Future<void> _open() async {
    if (!_db.isConnected) await _db.open();
    await repairStuckCostDeletes(_db);
    final schema = await _db.collection('_sql_metadata').findOne({
      '_id': 'product_schema_v2',
    });
    if (schema == null) {
      throw StateError('Chưa có cấu trúc sản phẩm hiện hành.');
    }
  }

  @override
  Future<InventorySummary> summary() async {
    final counts = await Future.wait([
      _db.collection('SanPham').count({
        'DaXoa': {r'$ne': true},
      }),
      _db.collection('Xe').count({
        'DaXoa': {r'$ne': true},
      }),
      _db.collection('SanPham').count({
        'LoaiSanPham': 'phu_tung',
        'DaXoa': {r'$ne': true},
      }),
      _db.collection('Xe').count({
        'TinhTrangXe': 'chua_xac_dinh',
        'DaXoa': {r'$ne': true},
      }),
    ]);
    return InventorySummary(
      products: counts[0],
      vehicles: counts[1],
      parts: counts[2],
      unclassified: counts[3],
    );
  }

  static Map<String, dynamic> filterFor(
    InventorySection view,
    String search,
    String condition,
  ) {
    final filter = <String, dynamic>{
      'DaXoa': {r'$ne': true},
    };
    if (view == InventorySection.parts) filter['LoaiSanPham'] = 'phu_tung';
    if (view == InventorySection.vehicles && condition.isNotEmpty) {
      filter['TinhTrangXe'] = condition;
    }
    final term = search.trim();
    if (term.isNotEmpty) {
      filter[r'$or'] = [
        {
          view == InventorySection.vehicles ? 'TenXe' : 'TenSanPham': {
            r'$regex': RegExp.escape(term),
            r'$options': 'i',
          },
        },
        if (view != InventorySection.vehicles)
          {
            'MaSanPham': {r'$regex': RegExp.escape(term), r'$options': 'i'},
          },
        if (int.tryParse(term) != null)
          {
            view == InventorySection.vehicles ? 'IdXe' : 'IdSanPham': int.parse(
              term,
            ),
          },
      ];
    }
    return filter;
  }

  @override
  Future<InventoryPage> fetch(
    InventorySection view, {
    String search = '',
    String condition = '',
    String availability = 'all',
    int page = 0,
    int pageSize = 30,
  }) async {
    final collection = _db.collection(
      view == InventorySection.vehicles ? 'Xe' : 'SanPham',
    );
    final filter = filterFor(view, search, condition);
    if (view == InventorySection.vehicles) filter['DangNhapHang'] = null;
    if (view == InventorySection.vehicles && search.trim().isNotEmpty) {
      final pattern = {
        r'$regex': RegExp.escape(search.trim()),
        r'$options': 'i',
      };
      final extraFilter = {
        r'$or': [
          {'SoKhung': pattern},
          {'SoMay': pattern},
          {'BienSo': pattern},
        ],
      };
      final ids = <dynamic>{};
      for (final name in ['XeMoi', 'XeCu']) {
        final matches = await _db
            .collection(name)
            .modernFind(filter: extraFilter, projection: {'IdXe': 1})
            .toList();
        ids.addAll(matches.map((r) => r['IdXe']));
      }
      if (ids.isNotEmpty) {
        (filter[r'$or'] as List).add({
          'IdXe': {r'$in': ids.toList()},
        });
      }
    }
    if (view == InventorySection.vehicles && availability != 'all') {
      filter['TinhTrang'] = availability == 'available';
      if (availability == 'available') filter['GiuChoBanHang'] = null;
    }
    if (view == InventorySection.parts && availability != 'all') {
      final stocks = await _db.collection('TonKhoPhuTung').find({
        'SoLuongTon': availability == 'available' ? {r'$gt': 0} : {r'$lte': 0},
      }).toList();
      filter['IdSanPham'] = {
        r'$in': stocks.map((r) => r['IdSanPham']).toList(),
      };
    }
    final total = await collection.count(filter);
    final rows = await collection
        .modernFind(
          filter: filter,
          sort: {view == InventorySection.vehicles ? 'IdXe' : 'IdSanPham': 1},
          skip: pageSize <= 0 || page == 0 ? null : page * pageSize,
          limit: pageSize <= 0 ? null : pageSize,
        )
        .toList();
    if (rows.isNotEmpty && view == InventorySection.vehicles) {
      for (final row in rows) {
        row['SoLuongTon'] =
            row['TinhTrang'] == true && row['GiuChoBanHang'] == null
            ? 1
            : row['TinhTrang'] == false || row['GiuChoBanHang'] != null
            ? 0
            : null;
      }
      final ids = rows.map((r) => r['IdXe']).toList();
      final byId = {for (final row in rows) row['IdXe']: row};
      for (final name in ['XeMoi', 'XeCu']) {
        final details = await _db.collection(name).find({
          'IdXe': {r'$in': ids},
        }).toList();
        for (final detail in details) {
          byId[detail['IdXe']]?.addAll(
            Map<String, dynamic>.of(detail)..remove('_id'),
          );
        }
      }
    } else if (rows.isNotEmpty && view == InventorySection.parts) {
      final ids = rows.map((r) => r['IdSanPham']).toList();
      final receiptCosts = <dynamic, num>{};
      final receipts = await _db
          .collection('ChiTietNhapHang')
          .modernFind(
            filter: {
              'IdSanPham': {r'$in': ids},
            },
            projection: {'IdSanPham': 1, 'ChiPhi': 1},
          )
          .toList();
      for (final receipt in receipts) {
        final id = receipt['IdSanPham'];
        final costs = (receipt['ChiPhi'] as List? ?? [])
            .where((c) => c['DaXoa'] != true)
            .fold<num>(0, (sum, cost) => sum + (cost['SoTien'] as num? ?? 0));
        receiptCosts[id] = (receiptCosts[id] ?? 0) + costs;
      }
      final stocks = await _db.collection('TonKhoPhuTung').find({
        'IdSanPham': {r'$in': ids},
      }).toList();
      final byId = {for (final stock in stocks) stock['IdSanPham']: stock};
      for (final row in rows) {
        row['SoLuongTon'] = byId[row['IdSanPham']]?['SoLuongTon'];
        row['DaKiemKe'] = byId.containsKey(row['IdSanPham']);
        row['TongChiPhi'] =
            (row['TongChiPhi'] as num? ?? 0) +
            (receiptCosts[row['IdSanPham']] ?? 0);
      }
    }
    return InventoryPage(rows, total);
  }

  @override
  Future<Map<String, dynamic>> details(
    InventorySection view,
    Map<String, dynamic> row,
  ) async {
    if (view == InventorySection.vehicles) {
      final extensions = await Future.wait([
        _db.collection('XeMoi').findOne({'IdXe': row['IdXe']}),
        _db.collection('XeCu').findOne({'IdXe': row['IdXe']}),
      ]);
      final result = Map<String, dynamic>.of(row);
      for (final extension in extensions) {
        if (extension != null) result.addAll(Map.of(extension)..remove('_id'));
      }
      return result;
    }
    final id = row['IdSanPham'];
    if (row['LoaiSanPham'] == 'phu_tung') {
      final stock = await _db.collection('TonKhoPhuTung').findOne({
        'IdSanPham': id,
      });
      return {
        ...row,
        'SoLuongTon': stock?['SoLuongTon'],
        'DaKiemKe': stock != null,
      };
    }
    return {
      ...row,
      'SoChiecLienKet': await _db.collection('Xe').count({'IdSanPham': id}),
    };
  }

  @override
  Future<void> close() async {
    try {
      await _pendingConnection;
    } catch (_) {
      /* Connection already reported by the screen. */
    }
    if (_db.isConnected) await _db.close();
  }
}
