import '../models/maintenance/record_maintenance.dart';
import 'cost_delete_repair.dart';
import 'mongo_record_maintenance.dart';
import 'mongo_product_cash.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../core/config/database_config.dart';
import '../models/products/product_details.dart';
import '../models/repositories/product_details_repository.dart';

class MongoProductDetailsRepository implements ProductDetailsRepository {
  MongoProductDetailsRepository({String? uri})
    : _db = Db(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  @override
  RecordMaintenance get maintenance => MongoRecordMaintenance(_db, _connect);
  Future<void> _connect() async {
    if (!_db.isConnected) await _db.open(writeConcern: WriteConcern.journaled);
    await repairStuckCostDeletes(_db);
  }

  Map<String, dynamic> _identity(ProductReference p) => {
    p.vehicle ? 'IdXe' : 'IdSanPham': p.id,
  };

  @override
  Future<void> update(ProductReference p, ProductEditDraft draft) async {
    final error = draft.validate();
    if (error != null) throw StateError(error);
    await _connect();
    final collection = _db.collection(p.vehicle ? 'Xe' : 'SanPham');
    final current = await collection.findOne({
      ..._identity(p),
      'DaXoa': {r'$ne': true},
    });
    if (current == null) throw StateError('Sản phẩm không còn tồn tại.');
    if (current['GiuChoBanHang'] != null || current['DangNhapHang'] != null) {
      throw StateError('Sản phẩm đang được xử lý. Vui lòng thử lại sau.');
    }
    final price = draft.salePrice.trim().isEmpty
        ? null
        : int.parse(draft.salePrice);
    if (p.vehicle &&
        current['TinhTrang'] == false &&
        price != current['GiaBan']) {
      throw StateError(
        'Không sửa giá bán của xe đã bán để bảo toàn dữ liệu cũ.',
      );
    }
    final fields = <String, dynamic>{
      p.vehicle ? 'TenXe' : 'TenSanPham': draft.name.trim(),
      p.vehicle ? 'GiaBan' : 'GiaBanThamKhao': price,
      'GhiChu': draft.notes.trim(),
      'NgayCapNhat': DateTime.now().toUtc(),
    };
    if (p.vehicle) {
      final extension = _db.collection(
        current['TinhTrangXe'] == 'cu' ? 'XeCu' : 'XeMoi',
      );
      final r = await extension.updateOne(
        {'IdXe': p.id},
        {
          r'$set': {
            'SoKhung': draft.frame.trim(),
            'SoMay': draft.engine.trim(),
            'BienSo': draft.plate.trim(),
            'MauSon': draft.color.trim(),
            'GhiChu': draft.notes.trim(),
          },
        },
        upsert: true,
      );
      if (!r.isSuccess || r.hasWriteErrors) {
        throw StateError('Không lưu được thông tin xe.');
      }
    } else {
      if (draft.code.trim().isNotEmpty &&
          await collection.findOne({
                'MaSanPham': draft.code.trim(),
                'IdSanPham': {r'$ne': p.id},
                'DaXoa': {r'$ne': true},
              }) !=
              null) {
        throw StateError('Mã sản phẩm đã được sử dụng.');
      }
      fields.addAll({
        'MaSanPham': draft.code.trim(),
        'DonViTinh': draft.unit.trim(),
      });
    }
    final r = await collection.updateOne(
      {
        ..._identity(p),
        'DaXoa': {r'$ne': true},
        if (p.vehicle) ...{
          'GiuChoBanHang': null,
          'SuaXoaDangLuu': null,
          'DangNhapHang': null,
          'TinhTrang': current['TinhTrang'],
        },
      },
      {r'$set': fields},
    );
    if (!r.isSuccess || r.hasWriteErrors || r.nMatched != 1) {
      throw StateError('Sản phẩm vừa thay đổi. Vui lòng tải lại và thử lại.');
    }
  }

  @override
  Future<void> archive(ProductReference p) async {
    await _connect();
    if (!p.vehicle) {
      final stock = await _db.collection('TonKhoPhuTung').findOne(_identity(p));
      if (stock?['SuaXoaDangLuu'] != null ||
          (stock?['GiuChoBanHang'] as Map?)?.isNotEmpty == true) {
        throw StateError('Phụ tùng đang có giao dịch được lưu.');
      }
    }
    final result = await _db
        .collection(p.vehicle ? 'Xe' : 'SanPham')
        .updateOne(
          {
            ..._identity(p),
            'GiuChoBanHang': null,
            'SuaXoaDangLuu': null,
            'DangNhapHang': null,
          },
          {
            r'$set': {'DaXoa': true, 'NgayXoa': DateTime.now().toUtc()},
          },
        );
    if (!result.isSuccess || result.hasWriteErrors || result.nMatched != 1) {
      throw StateError('Sản phẩm đang được xử lý hoặc không còn tồn tại.');
    }
  }

  @override
  Future<void> delete(ProductReference p) async {
    await _connect();
    for (final name in [
      'HoaDonBan',
      'HoaDonMua',
      'ChiTietNhapHang',
      'ChiTietHoaDonBan',
      'ChiTietHoaDonMua',
    ]) {
      if (await _db.collection(name).findOne(_identity(p)) != null) {
        throw StateError('Không thể xóa sản phẩm đã có phiếu nhập hoặc bán.');
      }
    }
    final current = await _db
        .collection(p.vehicle ? 'Xe' : 'SanPham')
        .findOne(_identity(p));
    if (current == null || current['DaXoa'] == true) {
      throw StateError('Sản phẩm không còn tồn tại.');
    }
    if (current['IdNhapHang'] != null ||
        current['TinhTrang'] == false ||
        (current['ChiPhi'] as List? ?? []).isNotEmpty) {
      throw StateError('Không thể xóa sản phẩm đã có giao dịch hoặc chi phí.');
    }
    if (!p.vehicle) {
      final stock = await _db.collection('TonKhoPhuTung').findOne(_identity(p));
      if ((stock?['GiuChoBanHang'] as Map?)?.isNotEmpty == true) {
        throw StateError('Sản phẩm đang được giữ cho đơn bán.');
      }
      if ((stock?['SoLuongTon'] as num? ?? 0) != 0) {
        throw StateError('Sản phẩm còn tồn kho, không thể xóa.');
      }
    }
    final r = await _db
        .collection(p.vehicle ? 'Xe' : 'SanPham')
        .updateOne(
          {
            ..._identity(p),
            'GiuChoBanHang': null,
            'SuaXoaDangLuu': null,
            'DangNhapHang': null,
          },
          {
            r'$set': {'DaXoa': true, 'NgayXoa': DateTime.now().toUtc()},
          },
        );
    if (!r.isSuccess || r.hasWriteErrors || r.nMatched != 1) {
      throw StateError('Sản phẩm đang được xử lý, không thể xóa.');
    }
  }

  @override
  Future<ProductDetails> load(ProductReference product) async {
    await _connect();
    final info = await _db
        .collection(product.vehicle ? 'Xe' : 'SanPham')
        .findOne(_identity(product));
    if (info == null || info['DaXoa'] == true) {
      throw StateError('Sản phẩm không còn tồn tại.');
    }
    if (product.vehicle) {
      for (final collection in ['XeMoi', 'XeCu']) {
        final extension = await _db.collection(collection).findOne({
          'IdXe': product.id,
        });
        if (extension != null) info.addAll(Map.of(extension)..remove('_id'));
      }
      info['SoLuongTon'] =
          info['TinhTrang'] == true && info['GiuChoBanHang'] == null ? 1 : 0;
    } else {
      final stock = await _db.collection('TonKhoPhuTung').findOne({
        'IdSanPham': product.id,
      });
      info['SoLuongTon'] = stock?['SoLuongTon'];
    }
    final sales = await _orders(
      product,
      'ChiTietHoaDonBan',
      'HoaDonBan',
      'IdHoaDon',
      'NgayMua',
      'Đơn bán',
    );
    final receipts = await _orders(
      product,
      'ChiTietHoaDonMua',
      'HoaDonMua',
      'IdMua',
      'NgayBan',
      'Đơn mua',
    );
    final details = await _db
        .collection('ChiTietNhapHang')
        .find(_identity(product))
        .toList();
    final batchIds = <int>{
      if (product.vehicle && info['IdNhapHang'] is num)
        (info['IdNhapHang'] as num).toInt(),
      for (final d in details)
        if (d['IdNhapHang'] is num) (d['IdNhapHang'] as num).toInt(),
    };
    for (final id in batchIds) {
      final batch = await _db.collection('NhapHang').findOne({
        'IdNhapHang': id,
      });
      if (batch != null) {
        receipts.add(
          {
            'Ma': id,
            'Loai': 'Lô hàng',
            'Ngay': batch['NgayNhap'],
            'DoiTac': await _partnerName(batch['IdDoiTac'], batch['NoiNhap']),
            'SoLuong': details
                .where((d) => d['IdNhapHang'] == id)
                .fold<num>(0, (s, d) => s + (d['SoLuong'] as num? ?? 0)),
            'SoTien': details
                .where((d) => d['IdNhapHang'] == id)
                .fold<num>(
                  0,
                  (s, d) =>
                      s +
                      (d['GiaNhap'] as num? ?? 0) * (d['SoLuong'] as num? ?? 0),
                ),
            'GhiChu': batch['GhiChu'],
          }..addAll(
            details.any((d) => d['IdNhapHang'] == id)
                ? {}
                : {'SoLuong': 1, 'SoTien': info['GiaNhap']},
          ),
        );
      }
    }
    final costs = <Map<String, dynamic>>[];
    void addCosts(
      String collection,
      Map<String, dynamic> row, {
      String? label,
    }) {
      final entries = row['ChiPhi'] as List? ?? [];
      for (var i = 0; i < entries.length; i++) {
        final cost = Map<String, dynamic>.from(entries[i] as Map);
        if (cost['DaXoa'] == true) continue;
        costs.add({
          ...cost,
          '_CostCollection': collection,
          '_CostDocument': row['_id'],
          '_CostIndex': i,
          if (label != null) 'Nguon': label,
        });
      }
    }

    addCosts(product.vehicle ? 'Xe' : 'SanPham', info);
    if (!product.vehicle) {
      for (final detail in details) {
        addCosts(
          'ChiTietNhapHang',
          detail,
          label: 'Lô #${detail['IdNhapHang']}',
        );
      }
    }
    costs.sort(
      (a, b) => ((b['Ngay'] as DateTime?) ?? DateTime(1900)).compareTo(
        (a['Ngay'] as DateTime?) ?? DateTime(1900),
      ),
    );
    receipts.sort(
      (a, b) => ((b['Ngay'] as DateTime?) ?? DateTime(1900)).compareTo(
        (a['Ngay'] as DateTime?) ?? DateTime(1900),
      ),
    );
    return ProductDetails(
      information: info,
      sales: sales,
      receipts: receipts,
      costs: costs,
    );
  }

  Future<String?> _partnerName(dynamic id, dynamic fallback) async {
    if (id != null) {
      final partner = await _db.collection('DoiTac').findOne({'_id': id});
      final name = partner?['TenDoiTac']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return fallback?.toString();
  }

  Future<List<Map<String, dynamic>>> _orders(
    ProductReference p,
    String detailCollection,
    String headerCollection,
    String key,
    String dateKey,
    String kind,
  ) async {
    final lines = await _db
        .collection(detailCollection)
        .find(_identity(p))
        .toList();
    final ids = lines.map((r) => r[key]).toSet();
    final headers = await _db.collection(headerCollection).find({
      r'$or': [
        _identity(p),
        if (ids.isNotEmpty)
          {
            key: {r'$in': ids.toList()},
          },
      ],
      'TrangThaiLuu': {r'$ne': 'dang_luu'},
    }).toList();
    final result = <Map<String, dynamic>>[];
    for (final header in headers) {
      final matching = lines.where((r) => r[key] == header[key]).toList();
      final amounts = matching
          .map(
            (r) =>
                r['ThanhTien'] ??
                (r['DonGia'] is num
                    ? (r['DonGia'] as num) * (r['SoLuong'] as num? ?? 1)
                    : null),
          )
          .toList();
      result.add({
        'Ma': header[key],
        'Loai': kind,
        'Ngay': header[dateKey],
        'GhiChu': header['GhiChu'],
        if (headerCollection == 'HoaDonMua')
          'DoiTac': await _partnerName(header['IdDoiTac'], header['TenDoiTac']),
        'SoLuong': matching.isEmpty
            ? 1
            : matching.fold<num>(0, (s, r) => s + (r['SoLuong'] as num? ?? 1)),
        'SoTien': amounts.isNotEmpty && amounts.every((a) => a is num)
            ? amounts.fold<num>(0, (s, a) => s + (a as num))
            : headerCollection == 'HoaDonMua'
            ? header['GiaBan']
            : null,
      });
    }
    result.sort(
      (a, b) => ((b['Ngay'] as DateTime?) ?? DateTime(1900)).compareTo(
        (a['Ngay'] as DateTime?) ?? DateTime(1900),
      ),
    );
    return result;
  }

  @override
  Future<void> addCost(
    ProductReference product, {
    required DateTime date,
    required int amount,
    required String notes,
    required String requestId,
  }) async {
    if (amount < 0 || amount > 1000000000000000 || notes.length > 10000) {
      throw ArgumentError('Chi phí không hợp lệ');
    }
    await _connect();
    final collection = _db.collection(product.vehicle ? 'Xe' : 'SanPham');
    final cost = {
      'Ngay': DateTime.utc(date.year, date.month, date.day),
      'SoTien': amount,
      'GhiChu': notes.trim(),
      'MaYeuCau': requestId,
    };
    // $ne on an array field still matches when another cost has a different
    // request id, so a retry of the second cost would be inserted again.
    final result = await collection.updateOne(
      {
        ..._identity(product),
        'DaXoa': {r'$ne': true},
        'SuaXoaDangLuu': null,
        r'$or': [
          {
            'ChiPhi': {r'$exists': false},
          },
          {
            'ChiPhi': {
              r'$not': {
                r'$elemMatch': {'MaYeuCau': requestId},
              },
            },
          },
        ],
      },
      {
        r'$push': {'ChiPhi': cost},
        r'$inc': {'TongChiPhi': amount},
      },
    );
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Chưa xác nhận lưu chi phí');
    }
    if (result.nMatched == 0) {
      final saved = await collection.findOne({
        ..._identity(product),
        'DaXoa': {r'$ne': true},
        'ChiPhi': {
          r'$elemMatch': {'MaYeuCau': requestId},
        },
      });
      if (saved == null) {
        final current = await collection.findOne({
          ..._identity(product),
          'DaXoa': {r'$ne': true},
        });
        if (current == null) throw StateError('Sản phẩm không còn tồn tại.');
        if (current['SuaXoaDangLuu'] != null) {
          throw StateError('Sản phẩm đang được xử lý. Vui lòng thử lại sau.');
        }
        throw StateError('Chưa lưu được chi phí. Vui lòng thử lại.');
      }
    }
    await MongoProductCash.record(
      _db,
      source: product.vehicle ? 'Xe' : 'SanPham',
      productId: _identity(product).values.single,
      cost: cost,
      sourceKey: requestId,
    );
  }

  @override
  Future<void> close() async {
    if (_db.isConnected) await _db.close();
  }
}
