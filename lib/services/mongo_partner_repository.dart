import 'package:mongo_dart/mongo_dart.dart';
import '../core/config/database_config.dart';
import '../models/customers/customer_models.dart';
import '../models/repositories/partner_repository.dart';
import 'mongo_directory_repository.dart';

class MongoPartnerRepository extends MongoDirectoryRepository
    implements PartnerRepository {
  MongoPartnerRepository({super.uri})
    : _db = Db(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  Future<void>? _opening;
  Future<void> _connect() => _opening ??= _open().whenComplete(() {
    _opening = null;
  });
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open();
  }

  @override
  Future<CustomerPage> fetchPartners({String search = '', int page = 0}) async {
    await _connect();
    final term = search.trim();
    final regex = {r'$regex': RegExp.escape(term), r'$options': 'i'};
    final filter = <String, dynamic>{
      'DaXoa': {r'$ne': true},
      if (term.isNotEmpty)
        r'$or': [
          for (final field in [
            'TenDoiTac',
            'SoDienThoai',
            'DiaChi',
            'MaSoThue',
            'NguoiDaiDien',
          ])
            {field: regex},
        ],
    };
    final collection = _db.collection('DoiTac');
    final total = await collection.count(filter);
    final rows = await collection
        .modernFind(
          filter: filter,
          sort: {'NgayTao': -1, '_id': -1},
          skip: page == 0 ? null : page * 30,
          limit: 30,
        )
        .toList();
    return CustomerPage(rows, total);
  }

  @override
  Future<Map<String, dynamic>?> findPartner(String id) async {
    await _connect();
    return _db.collection('DoiTac').findOne({'_id': id});
  }

  @override
  Future<CustomerOrderPage> purchaseOrders(
    String partnerId, {
    int page = 0,
  }) async {
    await _connect();
    final filter = {'IdDoiTac': partnerId};
    final total =
        await _db.collection('NhapHang').count(filter) +
        await _db.collection('HoaDonMua').count(filter);
    final limit = (page + 1) * 30;
    final batches = await _db
        .collection('NhapHang')
        .modernFind(
          filter: filter,
          sort: {'NgayNhap': -1, 'IdNhapHang': -1},
          limit: limit,
        )
        .toList();
    final purchases = await _db
        .collection('HoaDonMua')
        .modernFind(
          filter: filter,
          sort: {'NgayBan': -1, 'IdMua': -1},
          limit: limit,
        )
        .toList();
    final combined = <Map<String, dynamic>>[
      for (final row in batches)
        {
          ...row,
          'NguonDonNhap': 'NhapHang',
          'MaDonHang': row['IdNhapHang'],
          'NgayDonHang': row['NgayNhap'],
        },
      for (final row in purchases)
        {
          ...row,
          'NguonDonNhap': 'HoaDonMua',
          'MaDonHang': row['IdMua'],
          'NgayDonHang': row['NgayBan'],
        },
    ];
    combined.sort((a, b) {
      final date = ((b['NgayDonHang'] as DateTime?) ?? DateTime(1900))
          .compareTo((a['NgayDonHang'] as DateTime?) ?? DateTime(1900));
      if (date != 0) return date;
      final id = (b['MaDonHang'] as num).compareTo(a['MaDonHang'] as num);
      return id != 0
          ? id
          : (a['NguonDonNhap'] as String).compareTo(
              b['NguonDonNhap'] as String,
            );
    });
    final rows = combined.skip(page * 30).take(30).toList();
    if (rows.isEmpty) return CustomerOrderPage(rows, total);
    final ids = rows
        .where((r) => r['NguonDonNhap'] == 'NhapHang')
        .map((r) => r['IdNhapHang'])
        .toList();
    final details = await _db.collection('ChiTietNhapHang').find({
      'IdNhapHang': {r'$in': ids},
    }).toList();
    final legacy = await _db.collection('XeMoi').find({
      'IdNhapHang': {r'$in': ids},
    }).toList();
    final vehicleIds = legacy.map((d) => d['IdXe']).toList();
    final vehicles = vehicleIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _db.collection('Xe').find({
            'IdXe': {r'$in': vehicleIds},
          }).toList();
    final vehicleNames = {for (final v in vehicles) v['IdXe']: v['TenXe']};
    final purchaseIds = rows
        .where((r) => r['NguonDonNhap'] == 'HoaDonMua')
        .map((r) => r['IdMua'])
        .toList();
    final purchaseLines = purchaseIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _db.collection('ChiTietHoaDonMua').find({
            'IdMua': {r'$in': purchaseIds},
          }).toList();
    final catalogIds = purchaseLines
        .map((l) => l['IdSanPham'])
        .where((id) => id != null)
        .toSet()
        .toList();
    final catalog = catalogIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _db.collection('SanPham').find({
            'IdSanPham': {r'$in': catalogIds},
          }).toList();
    final catalogNames = {
      for (final product in catalog)
        product['IdSanPham']: product['TenSanPham'],
    };
    for (final row in rows) {
      if (row['NguonDonNhap'] == 'HoaDonMua') {
        final items = purchaseLines
            .where((l) => l['IdMua'] == row['IdMua'])
            .toList();
        if (items.isEmpty && row['IdXe'] != null) {
          final vehicle = await _db.collection('Xe').findOne({
            'IdXe': row['IdXe'],
          });
          row['SanPhamHienThi'] =
              '${vehicle?['TenXe'] ?? 'Xe'} (#${row['IdXe']})';
        } else {
          row['SanPhamHienThi'] = items
              .map(
                (l) =>
                    '${l['TenSanPham'] ?? catalogNames[l['IdSanPham']] ?? 'Sản phẩm'}${l['IdXe'] == null ? '' : ' (#${l['IdXe']})'}',
              )
              .join(', ');
        }
        row['TongSoLuong'] = items.isEmpty
            ? 1
            : items.fold<num>(0, (sum, l) => sum + (l['SoLuong'] as num? ?? 1));
        row['TongTien'] =
            row['GiaBan'] ??
            (items.isNotEmpty &&
                    items.every(
                      (l) => l['DonGia'] is num && l['SoLuong'] is num,
                    )
                ? items.fold<num>(
                    0,
                    (sum, l) =>
                        sum + (l['DonGia'] as num) * (l['SoLuong'] as num),
                  )
                : null);
        continue;
      }
      final names = <String, String>{};
      for (final d in legacy.where(
        (d) => d['IdNhapHang'] == row['IdNhapHang'],
      )) {
        names['xe-${d['IdXe']}'] =
            '${vehicleNames[d['IdXe']] ?? 'Xe'} (#${d['IdXe']})';
      }
      for (final d in details.where(
        (d) => d['IdNhapHang'] == row['IdNhapHang'],
      )) {
        names[d['IdXe'] == null ? 'detail-${d['_id']}' : 'xe-${d['IdXe']}'] =
            '${d['TenSanPham'] ?? 'Sản phẩm #${d['IdSanPham']}'}${d['IdXe'] == null ? '' : ' (#${d['IdXe']})'}';
      }
      row['MaDonHang'] = row['IdNhapHang'];
      row['NgayDonHang'] = row['NgayNhap'];
      row['SanPhamHienThi'] = names.values.join(', ');
      row['TongSoLuong'] = row['SoLuong'];
      row['TongTien'] = row['SoTien'];
    }
    return CustomerOrderPage(rows, total);
  }

  @override
  Future<void> close() async {
    await super.close();
    try {
      await _opening;
    } catch (_) {
      /* Screen reports errors. */
    }
    if (_db.isConnected) await _db.close();
  }
}
