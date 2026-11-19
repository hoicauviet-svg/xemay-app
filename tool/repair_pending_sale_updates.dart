// Repairs order changes whose stored plan cannot pass the HoaDonBan validator
// (new-format sales where deleting/editing a payment broke the cash or debt
// date rules). Dry-run by default; pass --apply to write.
//
//   dart run tool/repair_pending_sale_updates.dart --uri=mongodb://host:27017/XM
//   dart run tool/repair_pending_sale_updates.dart --uri=... --apply
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/maintenance/record_maintenance.dart';
import 'package:xemay_app/services/mongo_record_maintenance.dart';
import 'package:xemay_app/services/mongo_sync_journal.dart';

const _defaultUri = 'mongodb://127.0.0.1:27017/XM';

bool _sameValue(dynamic left, dynamic right) {
  if (left is DateTime && right is DateTime) {
    return left.millisecondsSinceEpoch == right.millisecondsSinceEpoch;
  }
  return left == right;
}

DateTime? _date(dynamic value) =>
    value is DateTime ? DateTime.utc(value.year, value.month, value.day) : null;

DateTime _nextMonth(DateTime value) {
  final lastDay = DateTime.utc(value.year, value.month + 2, 0).day;
  return DateTime.utc(
    value.year,
    value.month + 1,
    value.day > lastDay ? lastDay : value.day,
  );
}

/// Mirrors the deployed HoaDonBan validator for the fields touched here.
bool _headerValid(Map<String, dynamic> doc) {
  if (doc['IdHoaDon'] is! num) return false;
  if (doc['PhienBanBanHang'] == 3) {
    final goods = doc['TongTienHang'],
        discount = doc['GiamGia'],
        total = doc['TongThanhToan'],
        cash = doc['SoTienKhachDua'],
        paid = doc['SoTienDaTra'],
        due = doc['SoTienConNo'],
        change = doc['TienThua'];
    if ([
      goods,
      discount,
      total,
      cash,
      paid,
      due,
      change,
    ].any((value) => value is! num || value < 0)) {
      return false;
    }
    if (total != goods - discount) return false;
    if (paid != (cash < total ? cash : total)) return false;
    if (due != total - paid) return false;
    if (change != cash - paid) return false;
    if (doc['MaYeuCauLuu'] is! String) return false;
    if (!['dang_luu', 'da_luu'].contains(doc['TrangThaiLuu'])) return false;
    if (doc['NgayMua'] is! DateTime) return false;
  }
  if (doc['PhienBanNgayCongNo'] == 1) {
    final due = doc['SoTienConNo'];
    if (due is! num) return false;
    if (due > 0) {
      final sale = _date(doc['NgayMua']),
          dueDate = _date(doc['NgayHen']),
          interest = _date(doc['NgayTinhLai']);
      if (sale == null || dueDate == null || interest == null) return false;
      if (dueDate.isBefore(sale) || interest.isBefore(sale)) return false;
      if (doc['IdKH'] is! num) return false;
    }
  }
  final numeric = [
    'TongTienHang',
    'GiamGia',
    'TongThanhToan',
    'SoTienKhachDua',
    'SoTienDaTra',
    'SoTienConNo',
    'TienThua',
  ];
  for (final key in numeric) {
    if (doc.containsKey(key) && (doc[key] is! num || (doc[key] as num) < 0)) {
      return false;
    }
  }
  for (final key in ['NgayMua', 'NgayHen', 'NgayTinhLai']) {
    if (doc.containsKey(key) && doc[key] != null && doc[key] is! DateTime) {
      return false;
    }
  }
  return true;
}

Future<void> main(List<String> args) async {
  final uriArg = args
      .firstWhere((arg) => arg.startsWith('--uri='), orElse: () => '')
      .replaceFirst('--uri=', '');
  final apply = args.contains('--apply');
  final uri = uriArg.isEmpty ? _defaultUri : uriArg;
  final db = SyncTrackedDb(uri);
  await db.open(writeConcern: WriteConcern.journaled);
  final maintenance = MongoRecordMaintenance(db, () async {});
  stdout.writeln('${apply ? 'ÁP DỤNG' : 'CHẠY THỬ'} trên $uri');
  var fixed = 0, skipped = 0, failed = 0;
  try {
    final plans = await db.collection('_record_changes').find({
      'Kind': 'order',
      'State': 'pending',
    }).toList();
    if (plans.isEmpty) {
      stdout.writeln('Không có kế hoạch sửa/xóa đơn hàng nào đang chờ xử lý.');
      return;
    }
    for (final plan in plans) {
      final id = plan['_id'];
      final parent = (plan['Parent'] as num).toInt();
      final operations = (plan['Operations'] as List).cast<Map>();
      final index = operations.indexWhere(
        (step) => step['Collection'] == 'HoaDonBan' && step['Fields'] != null,
      );
      if (index < 0) {
        stdout.writeln(
          'Bỏ qua đơn #$parent (${plan['_id']}): không có bước cập nhật HoaDonBan.',
        );
        skipped++;
        continue;
      }
      final step = Map<String, dynamic>.from(operations[index]);
      final original = Map<String, dynamic>.from(step['Fields'] as Map);
      final fields = Map<String, dynamic>.from(original);
      final header = await db.collection('HoaDonBan').findOne({
        '_id': step['Id'],
      });
      final debt = await db.collection('SoNo').findOne({'IdHoaDon': parent});
      if (header == null) {
        stdout.writeln('Bỏ qua đơn #$parent: không tìm thấy đơn hàng.');
        skipped++;
        continue;
      }
      final candidate = <String, dynamic>{...header, ...fields};
      if (_headerValid(candidate)) {
        stdout.writeln(
          'Bỏ qua đơn #$parent: dữ liệu sẽ ghi đã hợp lệ (lỗi không phải do validator).',
        );
        skipped++;
        continue;
      }
      num? paid = fields['SoTienDaTra'] as num? ?? debt?['SoTienDaTra'] as num?;
      num? due = fields['SoTienConNo'] as num? ?? debt?['SoTienConNo'] as num?;
      if (header['PhienBanBanHang'] == 3) {
        final total =
            (fields['TongThanhToan'] ?? header['TongThanhToan']) as num?;
        if (paid == null || total == null) {
          stdout.writeln('Bỏ qua đơn #$parent: thiếu số đã trả/tổng tiền.');
          skipped++;
          continue;
        }
        final previousChange =
            (fields['TienThua'] ?? header['TienThua'] ?? 0) as num;
        final change = paid >= total ? previousChange : 0;
        fields['SoTienDaTra'] = paid;
        fields['SoTienConNo'] = total - paid;
        fields['SoTienKhachDua'] = paid + change;
        fields['TienThua'] = change;
        due = total - paid;
      }
      if (header['PhienBanNgayCongNo'] == 1 && (due ?? 0) > 0) {
        final sale = _date(fields['NgayMua'] ?? header['NgayMua']);
        if (sale == null) {
          stdout.writeln('Bỏ qua đơn #$parent: thiếu ngày bán.');
          skipped++;
          continue;
        }
        DateTime? valid(dynamic value) {
          final date = _date(value);
          return date == null || date.isBefore(sale) ? null : date;
        }

        fields['NgayTinhLai'] =
            valid(fields['NgayTinhLai']) ??
            valid(header['NgayTinhLai']) ??
            sale;
        fields['NgayHen'] =
            valid(fields['NgayHen']) ??
            valid(header['NgayHen']) ??
            _nextMonth(sale);
      }
      final corrected = <String, dynamic>{...header, ...fields};
      if (!_headerValid(corrected)) {
        stdout.writeln(
          'Bỏ qua đơn #$parent: không thể sửa tự động (dữ liệu còn vi phạm quy tắc khác).',
        );
        skipped++;
        continue;
      }
      final changes = <String>[
        for (final entry in fields.entries)
          if (!_sameValue(entry.value, original[entry.key]))
            '${entry.key}=${original[entry.key]} → ${entry.value}',
      ];
      stdout.writeln('Đơn #$parent (yêu cầu $id):');
      for (final line in changes) {
        stdout.writeln('  $line');
      }
      if (!apply) {
        stdout.writeln('  (chạy thử; thêm --apply để ghi)');
        continue;
      }
      try {
        final unset =
            (step['Unset'] as List?)?.cast<String>() ?? const <String>[];
        final write = await db
            .collection('HoaDonBan')
            .updateOne(
              {'_id': step['Id']},
              {
                if (fields.isNotEmpty) r'$set': fields,
                if (unset.isNotEmpty)
                  r'$unset': {for (final key in unset) key: ''},
              },
            );
        if (!write.isSuccess || write.hasWriteErrors) {
          stdout.writeln(
            'LỖI ghi đơn #$parent: ${write.writeError?.errmsg ?? write.writeError} '
            '${write.writeConcernError?.errmsg ?? write.writeConcernError}',
          );
          failed++;
          continue;
        }
        await db
            .collection('_record_changes')
            .updateOne(
              {'_id': id},
              {
                r'$set': {'Operations.$index.Fields': fields},
              },
            );
        await maintenance.recover(RecordKind.order, parent);
        final finished = await db.collection('_record_changes').findOne({
          '_id': id,
        });
        final locked = await db.collection('HoaDonBan').count({
          'SuaXoaDangLuu': id,
        });
        final finalHeader = await db.collection('HoaDonBan').findOne({
          '_id': step['Id'],
        });
        final ok = finished?['State'] == 'done' && locked == 0;
        stdout.writeln(
          '  ${ok ? 'HOÀN TẤT' : 'CHƯA HOÀN TẤT'} · nợ ${finalHeader?['SoTienConNo']} '
          '· đã trả ${finalHeader?['SoTienDaTra']} · khách đưa '
          '${finalHeader?['SoTienKhachDua']} · thừa ${finalHeader?['TienThua']}',
        );
        if (ok) {
          fixed++;
        } else {
          failed++;
        }
      } catch (error) {
        stdout.writeln('LỖI khi hoàn tất đơn #$parent: $error');
        failed++;
      }
    }
    stdout.writeln(
      'Kết quả: $fixed đã xử lý, $skipped bỏ qua, $failed lỗi'
      '${apply ? '' : ' (chạy thử, chưa ghi gì)'}.',
    );
  } finally {
    await db.close();
  }
}
