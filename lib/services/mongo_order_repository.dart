import 'customer_address_migration.dart';
import '../models/maintenance/record_maintenance.dart';
import 'mongo_record_maintenance.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../core/config/database_config.dart';
import '../models/orders/order_details.dart';
import '../models/repositories/order_repository.dart';

class MongoOrderRepository implements OrderRepository {
  MongoOrderRepository({
    String? uri,
    this.checkpoint,
    DateTime Function()? today,
  }) : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri),
       _today = today ?? DateTime.now;
  final DateTime Function() _today;
  final Db _db;
  bool _addressesReady = false;
  @override
  RecordMaintenance get maintenance => MongoRecordMaintenance(_db, _connect);

  final Future<void> Function(String)? checkpoint;
  Future<void> _connect() async {
    if (!_db.isConnected) await _db.open(writeConcern: WriteConcern.journaled);
    if (!_addressesReady) {
      await migrateCustomerAddresses(_db);
      _addressesReady = true;
    }
  }

  Future<void> _checked(Future<dynamic> operation) async {
    final result = await operation;
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Chưa xác nhận ghi dữ liệu');
    }
  }

  Future<void> _recover(int orderId) async {
    final debts = await _db.collection('SoNo').find({
      'IdHoaDon': orderId,
      'ThanhToanDangLuu': {r'$type': 'object'},
    }).toList();
    for (final debt in debts) {
      await _finish(debt);
    }
  }

  Future<void> _finish(Map<String, dynamic> debt) async {
    final pending = Map<String, dynamic>.from(debt['ThanhToanDangLuu'] as Map);
    final version = debt['PhienBanThanhToan'] as num;
    final cash = pending.remove('ThuLaiDangLuu');
    final customerGiven = pending.remove('TongTienKhachDuaSauTra');
    final nextAppointment = pending['NgayHenSauTra'];
    final payment = {...pending, 'SoCoNo': debt['SoTienConNo']};
    await _checked(
      _db
          .collection('TraNo')
          .updateOne(
            {'_id': payment['_id']},
            {r'$setOnInsert': payment},
            upsert: true,
          ),
    );
    if (checkpoint != null) await checkpoint!('afterHistory');
    if (cash is Map) {
      await _checked(
        _db
            .collection('ThuChiKhac')
            .updateOne(
              {'_id': cash['_id']},
              {r'$setOnInsert': Map<String, dynamic>.from(cash)},
              upsert: true,
            ),
      );
      if (checkpoint != null) await checkpoint!('afterInterest');
    }
    await _checked(
      _db
          .collection('HoaDonBan')
          .updateOne(
            {
              'IdHoaDon': debt['IdHoaDon'],
              r'$or': [
                {
                  'PhienBanThanhToan': {r'$exists': false},
                },
                {
                  'PhienBanThanhToan': {r'$lte': version},
                },
              ],
            },
            {
              r'$set': {
                'SoTienDaTra': (debt['SoTienDaTra'] as num).toInt(),
                'SoTienConNo': (debt['SoTienConNo'] as num).toInt(),
                if (nextAppointment is DateTime) 'NgayHen': nextAppointment,
                if ((pending['LaiThu'] as num? ?? 0) > 0)
                  'NgayTinhLai': pending['NgayTra'],
                'PhienBanThanhToan': version,
                'SoTienKhachDua': ?customerGiven,
              },
            },
          ),
    );
    await _checked(
      _db
          .collection('SoNo')
          .updateOne(
            {'_id': debt['_id'], 'ThanhToanDangLuu._id': pending['_id']},
            {
              r'$unset': {'ThanhToanDangLuu': ''},
            },
          ),
    );
  }

  @override
  Future<OrderDetails> load(int orderId) async {
    await _connect();
    await maintenance.ensureReadable(RecordKind.order, orderId);
    await _recover(orderId);
    final header = await _db.collection('HoaDonBan').findOne({
      'IdHoaDon': orderId,
      'TrangThaiLuu': {r'$ne': 'dang_luu'},
    });
    if (header == null) {
      throw const OrderException('Đơn hàng không còn tồn tại.');
    }
    final customer = header['IdKH'] == null
        ? null
        : await _db.collection('KhachHang').findOne({'IdKH': header['IdKH']});
    if (customer != null) {
      customer['DiaChiHienThi'] = customer['DiaChiChiTiet'] ?? '';
    }
    final lines = await _db
        .collection('ChiTietHoaDonBan')
        .modernFind(filter: {'IdHoaDon': orderId}, sort: {'DongSo': 1})
        .toList();
    final legacy = header['PhienBanBanHang'] == null;
    if (legacy && lines.isEmpty && header['IdXe'] != null) {
      final vehicle = await _db.collection('Xe').findOne({
        'IdXe': header['IdXe'],
      });
      if (vehicle != null) {
        lines.add({
          'IdXe': vehicle['IdXe'],
          'IdSanPham': vehicle['IdSanPham'],
          'TenSanPham': vehicle['TenXe'],
          'SoLuong': 1,
          'DonGiaHienThi': vehicle['GiaBan'],
        });
      }
    }
    for (final line in lines) {
      line['DonGiaHienThi'] ??= line['DonGia'];
      if (legacy && line['DonGiaHienThi'] == null) {
        if (line['DonGiaNguon'] is num) {
          line['DonGiaHienThi'] = line['DonGiaNguon'];
        } else if (line['IdXe'] != null) {
          final vehicle = await _db.collection('Xe').findOne({
            'IdXe': line['IdXe'],
          });
          line['DonGiaHienThi'] = vehicle?['GiaBan'];
        }
      }

      if (line['TenSanPham'] == null) {
        final catalog = line['IdSanPham'] == null
            ? null
            : await _db.collection('SanPham').findOne({
                'IdSanPham': line['IdSanPham'],
              });
        line['TenSanPham'] = catalog?['TenSanPham'] ?? '';
      }
      if (line['IdXe'] != null) {
        for (final name in ['XeMoi', 'XeCu']) {
          final ext = await _db.collection(name).findOne({
            'IdXe': line['IdXe'],
          });
          if (ext != null) {
            for (final key in ['SoKhung', 'SoMay', 'BienSo', 'MauSon']) {
              if (ext[key] != null) line[key] = ext[key];
            }
          }
        }
      }
    }
    final debts = await _db.collection('SoNo').find({
      'IdHoaDon': orderId,
    }).toList();
    final payments = debts.isEmpty
        ? <Map<String, dynamic>>[]
        : await _db
              .collection('TraNo')
              .modernFind(
                filter: {
                  'IdSoNo': {r'$in': debts.map((d) => d['IdSoNo']).toList()},
                },
                sort: {'NgayTra': -1, 'IdTraNo': -1},
              )
              .toList();
    return OrderDetails(
      header: header,
      customer: customer,
      lines: lines,
      debts: debts,
      payments: payments,
    );
  }

  Future<int> _nextPayment([
    String collection = 'TraNo',
    String field = 'IdTraNo',
  ]) async {
    final last = await _db
        .collection(collection)
        .modernFind(sort: {field: -1}, limit: 1)
        .toList();
    final counters = _db.collection('_app_counters');
    await _checked(
      counters.updateOne(
        {'_id': collection},
        {
          r'$max': {'value': last.isEmpty ? 0 : last.first[field]},
        },
        upsert: true,
      ),
    );
    final next = await counters.findAndModify(
      query: {'_id': collection},
      update: {
        r'$inc': {'value': 1},
      },
      returnNew: true,
    );
    return (next!['value'] as num).toInt();
  }

  @override
  Future<void> pay(
    int orderId, {
    required DateTime date,
    required int amount,
    int? interest,
    required String notes,
    required String requestId,
    DateTime? nextAppointment,
  }) async {
    if (amount < 0 || amount > 1000000000000000 || notes.length > 10000) {
      throw const OrderException('Số tiền thanh toán không hợp lệ.');
    }
    await _connect();
    await maintenance.ensureReadable(RecordKind.order, orderId);
    await _recover(orderId);
    final paymentId = 'order-payment-$requestId';
    final storedDate = DateTime.utc(date.year, date.month, date.day);
    if (await _db.collection('_record_deleted').findOne({
          '_id': 'TraNo:$paymentId',
        }) !=
        null) {
      throw StateError(
        'Phiếu trả nợ này đã được xóa. Tạo yêu cầu thanh toán mới nếu cần.',
      );
    }
    final existing = await _db.collection('TraNo').findOne({'_id': paymentId});
    if (existing != null) {
      final debt = await _db.collection('SoNo').findOne({
        'IdSoNo': existing['IdSoNo'],
        'IdHoaDon': orderId,
      });
      if (debt == null ||
          existing['SotienTra'] != amount ||
          existing['NgayTra'] != storedDate ||
          existing['GhiChu'] != notes.trim() ||
          (interest != null &&
              (existing['LaiThu'] as num?)?.round() != interest) ||
          (nextAppointment != null &&
              existing['NgayHenSauTra'] != OrderDetails.day(nextAppointment))) {
        throw const OrderException('Yêu cầu thanh toán đã thay đổi.');
      }
      return;
    }
    final header = await _db.collection('HoaDonBan').findOne({
      'IdHoaDon': orderId,
      'TrangThaiLuu': {r'$ne': 'dang_luu'},
    });
    if (header == null) {
      throw const OrderException('Đơn hàng không còn tồn tại.');
    }
    final debts = await _db.collection('SoNo').find({
      'IdHoaDon': orderId,
    }).toList();
    if (debts.length != 1) {
      throw const OrderException('Cần đối soát sổ nợ trước khi thanh toán.');
    }
    final debt = debts.single;
    if ((header['PhienBanThanhToan'] ?? 0) !=
            (debt['PhienBanThanhToan'] ?? 0) ||
        debt['ThanhToanDangLuu'] != null) {
      throw const OrderException(
        'Công nợ vừa thay đổi. Vui lòng tải lại đơn hàng.',
      );
    }
    final due = debt['SoTienConNo'], paid = debt['SoTienDaTra'];
    if (due is! num ||
        paid is! num ||
        !due.isFinite ||
        !paid.isFinite ||
        due < amount ||
        paid < 0) {
      throw const OrderException(
        'Số tiền thanh toán vượt số còn nợ hoặc công nợ chưa hợp lệ.',
      );
    }
    final orderDate = header['NgayMua'];
    if (orderDate is DateTime &&
        storedDate.isBefore(
          DateTime.utc(orderDate.year, orderDate.month, orderDate.day),
        )) {
      throw const OrderException(
        'Ngày thanh toán không được trước ngày đơn hàng.',
      );
    }
    final customer = await _db.collection('KhachHang').findOne({
      'IdKH': header['IdKH'],
    });
    final history = await _db.collection('TraNo').find({
      'IdSoNo': debt['IdSoNo'],
    }).toList();
    if (history.any(
      (p) =>
          p['NgayTra'] is DateTime &&
          OrderDetails.day(p['NgayTra'] as DateTime).isAfter(storedDate),
    )) {
      throw const OrderException(
        'Ngày thanh toán không được trước lần thanh toán gần nhất.',
      );
    }
    final details = OrderDetails(
      header: header,
      customer: customer,
      lines: const [],
      debts: debts,
      payments: history,
    );
    final charged = interest ?? details.interestAt(storedDate);
    if (charged < 0 || charged > 1000000000000000) {
      throw const OrderException('Số tiền lãi không hợp lệ.');
    }
    if (due <= 0 || (amount == 0 && charged == 0)) {
      throw const OrderException('Chưa có số tiền gốc hoặc tiền lãi cần thu.');
    }
    final cash = charged > 0
        ? {
            '_id': 'order-interest-$requestId',
            'ThuChiId': await _nextPayment('ThuChiKhac', 'ThuChiId'),
            'NgayThang': storedDate,
            'SoTien': charged,
            'ThuChi': true,
            'IdDanhMuc': 'customer-interest',
            'TenDanhMuc': 'Lãi khách hàng trả nợ',
            'IdHoaDon': orderId,
            'LyDo':
                'Thu tiền lãi của khách hàng ${customer?['TenKhachHang'] ?? ''} mã đơn hàng $orderId',
          }
        : null;
    if (nextAppointment != null &&
        OrderDetails.day(nextAppointment).isBefore(storedDate)) {
      throw const OrderException(
        'Ngày hẹn tiếp theo không được trước ngày thanh toán.',
      );
    }
    final pending = {
      '_id': paymentId,
      'IdTraNo': await _nextPayment(),
      'IdSoNo': debt['IdSoNo'],
      'SotienTra': amount,
      'NgayTra': storedDate,
      'GhiChu': notes.trim(),
      'SoTienLai': charged,
      'LaiThu': charged,
      'ThuLaiDangLuu': ?cash,
      'NgayHenSauTra': ?(nextAppointment == null
          ? details.nextAppointmentAt(_today())
          : OrderDetails.day(nextAppointment)),
      if (header['PhienBanBanHang'] == 3)
        'TongTienKhachDuaSauTra':
            (paid + amount + (header['TienThua'] as num? ?? 0)).toInt(),
      'NgayTinhLaiTruocTra': header['NgayTinhLai'],
      'NgayHenTruocTra': header['NgayHen'],
      'SoNgayQuaHan': 0,
      'LoaiTraNo': null,
    };
    final updated = await _db
        .collection('SoNo')
        .findAndModify(
          query: {
            '_id': debt['_id'],
            'IdHoaDon': orderId,
            'SoTienConNo': due,
            'SoTienDaTra': paid,
            'PhienBanThanhToan': debt['PhienBanThanhToan'],
            'ThanhToanDangLuu': null,
            'SuaXoaDangLuu': null,
          },
          update: {
            r'$inc': {
              'SoTienConNo': -amount,
              'SoTienDaTra': amount,
              'PhienBanThanhToan': 1,
            },
            r'$set': {'ThanhToanDangLuu': pending},
          },
          returnNew: true,
        );
    if (updated == null) {
      throw const OrderException(
        'Công nợ vừa thay đổi. Vui lòng tải lại đơn hàng.',
      );
    }
    if (checkpoint != null) await checkpoint!('afterDebt');
    await _finish(updated);
  }

  @override
  Future<void> close() async {
    if (_db.isConnected) await _db.close();
  }
}
