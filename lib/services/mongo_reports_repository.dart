import 'cost_delete_repair.dart';
import 'customer_address_migration.dart';
import '../models/maintenance/record_maintenance.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../core/config/database_config.dart';
import '../models/reports/report_models.dart';
import '../models/repositories/reports_repository.dart';

class MongoReportsRepository implements ReportsRepository {
  MongoReportsRepository({String? uri})
    : _db = Db(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  bool _addressesReady = false;
  Future<void>? _opening;
  Future<void> _connect() =>
      _opening ??= _open().whenComplete(() => _opening = null);
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open();
    if (!_addressesReady) {
      await migrateCustomerAddresses(_db);
      _addressesReady = true;
    }
    await repairStuckCostDeletes(_db);
  }

  Future<List<Map<String, dynamic>>> _read(
    String name,
    List<String> fields, {
    Map<String, dynamic>? filter,
  }) => _db
      .collection(name)
      .modernFind(
        filter: filter,
        projection: {'_id': 0, for (final field in fields) field: 1},
      )
      .toList();
  @override
  Future<ReportsData> load(ReportRange range) async {
    await _connect();
    if (await _db.collection('_record_changes').findOne({
          'State': {
            r'$in': ['pending', 'preparing'],
          },
        }) !=
        null) {
      throw const RecordChangeException(
        'Có phiếu sửa/xóa chưa hoàn tất. Vào Sản phẩm, bấm nút Tiếp tục xử lý thay đổi dang dở trước khi xem báo cáo.',
      );
    }
    final names = [
      'HoaDonBan',
      'ChiTietHoaDonBan',
      'Xe',
      'SoNo',
      'NhapHang',
      'SanPham',
      'TonKhoPhuTung',
      'NoCu',
      'VayVon',
      'CamDo',
      'TraNoCamDo',
      'ThuChiKhac',
      'KhachHang',
      'DichVu',
      'ChiTietNhapHang',
      'DoiTac',
      'VanChuyen',
      'TraNo',
      'TraNoNhapHang',
      'TraNoCu',
      'TraNoVayVon',
    ];
    final rows = await Future.wait([
      _read('HoaDonBan', [
        'IdHoaDon',
        'IdXe',
        'IdKH',
        'IdSanPham',
        'NgayMua',
        'NgayHen',
        'PhienBanBanHang',
        'TongTienHang',
        'GiamGia',
        'TongThanhToan',
        'SoTienDaTra',
        'SoTienKhachDua',
        'TrangThaiLuu',
      ]),
      _read('ChiTietHoaDonBan', [
        'GiaNhap',
        'TenSanPham',
        'IdSanPham',
        'IdDichVu',
        'LoaiSanPham',
        'DongSo',
        'IdHoaDon',
        'IdXe',
        'DonGia',
        'DonGiaNguon',
        'SoLuong',
      ]),
      _read('Xe', [
        'ChiPhi',
        'TongChiPhi',
        'TenXe',
        'IdXe',
        'GiaBan',
        'GiaNhap',
        'TinhTrang',
        'DaXoa',
        'TinhTrangXe',
        'DangNhapHang',
        'GiuChoBanHang',
      ]),
      _read('SoNo', [
        'IdSoNo',
        'IdHoaDon',
        'SoTienDaTra',
        'SoTienConNo',
        'ThanhToanDangLuu',
      ]),
      _read('NhapHang', [
        'LoaiSanPham',
        'IdDoiTac',
        'IdVanChuyen',
        'NoiNhap',
        'NguoiCho',
        'IdNhapHang',
        'NgayNhap',
        'NgayHen',
        'SoLuong',
        'SoTien',
        'SoTienDaTra',
        'SoTienConNo',
        'TrangThaiLuu',
        'ThanhToanDangLuu',
      ]),
      _read('SanPham', [
        'DaXoa',
        'IdSanPham',
        'LoaiSanPham',
        'TenSanPham',
        'ChiPhi',
        'TongChiPhi',
      ]),
      _read('TonKhoPhuTung', ['IdSanPham', 'SoLuongTon', 'GiaVonThamKhao']),
      _read('NoCu', ['Id', 'IdKH', 'SoCoNo', 'NgayHen', 'ThanhToanDangLuu']),
      _read('VayVon', [
        'IdVayVon',
        'DoiTac',
        'NgayVay',
        'SoTienVay',
        'TongConNo',
        'NgayHen',
        'ThanhToanDangLuu',
      ]),
      _read('CamDo', [
        'IdKhachHang',
        'TaiSanTheChap',
        'IdCamDo',
        'SoTienVay',
        'NgayVay',
        'NgayHan',
        'TrangThai',
        'ThanhToanDangLuu',
      ]),
      _read('TraNoCamDo', [
        'IdTraNoCamDo',
        'IdCamDo',
        'NgayTra',
        'TienGoc',
        'SoTienLai',
      ]),
      _read('ThuChiKhac', [
        'ThuChiId',
        'IdDanhMuc',
        'TenDanhMuc',
        'LyDo',
        'NgayThang',
        'ThuChi',
        'SoTien',
      ], filter: range.filter('NgayThang')),
      _read('KhachHang', [
        'IdKH',
        'TenKhachHang',
        'SoDienThoai',
        'DiaChiChiTiet',
      ]),
      _read('DichVu', ['_id', 'TenDichVu']),
      _read('ChiTietNhapHang', [
        'IdNhapHang',
        'SoLuong',
        'IdXe',
        'IdSanPham',
        'GiaNhap',
        'ChiPhi',
        'TongChiPhi',
      ]),
      _read('DoiTac', ['_id', 'TenDoiTac', 'SoDienThoai', 'DiaChi']),
      _read('VanChuyen', ['_id', 'TenVanChuyen']),
      _read('TraNo', [
        'IdTraNo',
        'IdSoNo',
        'NgayTra',
        'SotienTra',
        'LaiThu',
        'SoCoNo',
        'GhiChu',
        'LoaiThu',
      ], filter: range.filter('NgayTra')),
      _read('TraNoNhapHang', [
        'IdTraNoNhapHang',
        'IdNhapHang',
        'NgayTra',
        'SoTienTra',
        'SoCoNo',
        'GhiChu',
      ], filter: range.filter('NgayTra')),
      _read('TraNoCu', [
        'Id',
        'IdNoCu',
        'NgayTra',
        'SoTienTra',
        'LaiThu',
        'ConNo',
      ], filter: range.filter('NgayTra')),
      _read('TraNoVayVon', [
        'IdTraNoVayVon',
        'IdVayVon',
        'NgayTra',
        'SoTienTraGoc',
        'SoTienTraLai',
        'ConNoGoc',
      ], filter: range.filter('NgayTra')),
    ]);
    return ReportCalculator.build(
      range: range,
      source: {for (var i = 0; i < names.length; i++) names[i]: rows[i]},
    );
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {
      /* Connection failed. */
    }
    if (_db.isConnected) await _db.close();
  }
}
