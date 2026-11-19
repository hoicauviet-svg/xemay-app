// Verifies deleting/editing payments on new-format sales keeps the HoaDonBan
// document validator satisfied. Runs against a throwaway database.
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/maintenance/record_maintenance.dart';
import 'package:xemay_app/services/mongo_record_maintenance.dart';

const _ids = {
  'bsonType': ['int', 'long'],
};
const _nonneg = {
  'bsonType': ['int', 'long'],
  'minimum': 0,
};
const _totalFields = [
  'TongTienHang',
  'GiamGia',
  'TongThanhToan',
  'SoTienKhachDua',
  'SoTienDaTra',
  'SoTienConNo',
  'TienThua',
];

/// The deployed HoaDonBan validator (database_helper/sales_schema.py plus
/// upgrade_sale_debt_dates.with_debt_dates).
Map<String, dynamic> saleHeaderValidator() => {
  r'$and': [
    {
      r'$jsonSchema': {
        'bsonType': 'object',
        'required': ['IdHoaDon'],
        'properties': {
          'IdHoaDon': _ids,
          'IdKH': {
            'bsonType': ['int', 'long', 'null'],
          },
          for (final field in _totalFields) field: _nonneg,
          'NgayMua': {
            'bsonType': ['date', 'null'],
          },
        },
      },
    },
    {
      r'$or': [
        {
          'PhienBanBanHang': {r'$exists': false},
        },
        {
          r'$and': [
            {'PhienBanBanHang': 3},
            {
              r'$jsonSchema': {
                'required': [
                  ..._totalFields,
                  'MaYeuCauLuu',
                  'NgayMua',
                  'TrangThaiLuu',
                ],
                'properties': {
                  'MaYeuCauLuu': {'bsonType': 'string'},
                  'TrangThaiLuu': {
                    'enum': ['dang_luu', 'da_luu'],
                  },
                },
              },
            },
            {
              r'$expr': {
                r'$and': [
                  {
                    r'$eq': [
                      r'$TongThanhToan',
                      {
                        r'$subtract': [r'$TongTienHang', r'$GiamGia'],
                      },
                    ],
                  },
                  {
                    r'$eq': [
                      r'$SoTienDaTra',
                      {
                        r'$min': [r'$SoTienKhachDua', r'$TongThanhToan'],
                      },
                    ],
                  },
                  {
                    r'$eq': [
                      r'$SoTienConNo',
                      {
                        r'$subtract': [r'$TongThanhToan', r'$SoTienDaTra'],
                      },
                    ],
                  },
                  {
                    r'$eq': [
                      r'$TienThua',
                      {
                        r'$subtract': [r'$SoTienKhachDua', r'$SoTienDaTra'],
                      },
                    ],
                  },
                ],
              },
            },
          ],
        },
      ],
    },
    {
      r'$jsonSchema': {
        'properties': {
          'NgayHen': {
            'bsonType': ['date', 'null'],
          },
          'NgayTinhLai': {
            'bsonType': ['date', 'null'],
          },
        },
      },
    },
    {
      r'$or': [
        {
          'PhienBanNgayCongNo': {r'$exists': false},
        },
        {
          r'$and': [
            {'PhienBanNgayCongNo': 1},
            {
              r'$or': [
                {'SoTienConNo': 0},
                {
                  r'$and': [
                    {
                      'SoTienConNo': {r'$gt': 0},
                    },
                    {
                      r'$jsonSchema': {
                        'required': [
                          'IdKH',
                          'NgayMua',
                          'NgayHen',
                          'NgayTinhLai',
                        ],
                        'properties': {
                          'IdKH': _ids,
                          'NgayMua': {'bsonType': 'date'},
                          'NgayHen': {'bsonType': 'date'},
                          'NgayTinhLai': {'bsonType': 'date'},
                        },
                      },
                    },
                    {
                      r'$expr': {
                        r'$and': [
                          {
                            r'$gte': [r'$NgayHen', r'$NgayMua'],
                          },
                          {
                            r'$gte': [r'$NgayTinhLai', r'$NgayMua'],
                          },
                        ],
                      },
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};

int checks = 0;
void check(bool ok, String label) {
  if (!ok) throw StateError('FAIL: $label');
  checks++;
  stdout.writeln('PASS: $label');
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/QA_SALE_PAYMENT_DELETE_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final service = MongoRecordMaintenance(db, () async {});
  String token() => ObjectId().oid;
  Future<Map<String, dynamic>> get(String name, dynamic id) async =>
      (await db.collection(name).findOne({'_id': id}))!;
  Future<void> put(String name, Map<String, dynamic> row) async {
    await db.collection(name).insertOne(row);
  }

  Future<bool> valid(Map<String, dynamic> header) async {
    // The stored document was validated by MongoDB; re-check explicitly.
    final rows = await db.collection('HoaDonBan').find({
      r'$and': [
        saleHeaderValidator(),
        {'_id': header['_id']},
      ],
    }).toList();
    return rows.length == 1;
  }

  final sale = DateTime.utc(2026, 10, 1);
  final due = DateTime.utc(2026, 11, 1);
  try {
    await db.runCommand({
      'create': 'HoaDonBan',
      'validator': saleHeaderValidator(),
      'validationLevel': 'strict',
      'validationAction': 'error',
    });
    await put('KhachHang', {
      '_id': 'c',
      'IdKH': 1,
      'TenKhachHang': 'Khách thử',
    });

    Map<String, dynamic> newSale({
      required dynamic id,
      required int orderId,
      required int total,
      required int paid,
      required int cash,
      required int change,
      required int dueAmount,
      DateTime? dueDate,
      DateTime? interestDate,
      DateTime? saleDate,
      int? debtDatesVersion,
    }) => {
      '_id': id,
      'IdHoaDon': orderId,
      'IdKH': 1,
      'IdSoNo': orderId,
      'TongTienHang': total,
      'GiamGia': 0,
      'TongThanhToan': total,
      'SoTienKhachDua': cash,
      'SoTienDaTra': paid,
      'SoTienConNo': dueAmount,
      'TienThua': change,
      'PhienBanBanHang': 3,
      'PhienBanNgayCongNo': ?debtDatesVersion,
      'MaYeuCauLuu': 'req-$orderId',
      'TrangThaiLuu': 'da_luu',
      'NgayMua': saleDate ?? sale,
      'NgayHen': dueDate,
      'NgayTinhLai': interestDate,
    };
    Future<void> addPayment(
      int orderId,
      dynamic id,
      int principal,
      DateTime date, {
      int remaining = 0,
    }) async {
      await put('TraNo', {
        '_id': id,
        'IdTraNo': id,
        'IdSoNo': orderId,
        'NgayTra': date,
        'SotienTra': principal,
        'SoTienLai': 0,
        'LaiThu': 0,
        'SoCoNo': remaining,
      });
    }

    // A. Fully paid sale with change: deleting the checkout payment used to
    //    write cash = paid + change and fail the paid = min(cash, total) rule.
    await put(
      'HoaDonBan',
      newSale(
        id: 'a',
        orderId: 101,
        total: 10000000,
        paid: 10000000,
        cash: 10020000,
        change: 20000,
        dueAmount: 0,
        dueDate: due,
        interestDate: sale,
      ),
    );
    await put('SoNo', {
      '_id': 'debt-a',
      'IdSoNo': 101,
      'IdHoaDon': 101,
      'SoTienDaTra': 10000000,
      'SoTienConNo': 0,
    });
    await addPayment(101, 'sale:a:payment', 10000000, sale);
    await service.payment(
      RecordKind.order,
      101,
      'sale:a:payment',
      null,
      requestId: token(),
    );
    var header = await get('HoaDonBan', 'a');
    check(
      header['SoTienDaTra'] == 0 &&
          header['SoTienConNo'] == 10000000 &&
          header['SoTienKhachDua'] == 0 &&
          header['TienThua'] == 0,
      'Đơn trả đủ có tiền thừa: xóa phiếu đưa khách đưa/thừa về 0',
    );
    check(await valid(header), 'Header vẫn thỏa validator sau khi xóa');

    // B. Fully paid sale without debt dates: the sale gains debt and needs dates.
    await put(
      'HoaDonBan',
      newSale(
        id: 'b',
        orderId: 102,
        total: 10000000,
        paid: 10000000,
        cash: 10000000,
        change: 0,
        dueAmount: 0,
        debtDatesVersion: 1,
      ),
    );
    await put('SoNo', {
      '_id': 'debt-b',
      'IdSoNo': 102,
      'IdHoaDon': 102,
      'SoTienDaTra': 10000000,
      'SoTienConNo': 0,
    });
    await addPayment(102, 'sale:b:payment', 10000000, sale);
    await service.payment(
      RecordKind.order,
      102,
      'sale:b:payment',
      null,
      requestId: token(),
    );
    header = await get('HoaDonBan', 'b');
    check(
      header['SoTienDaTra'] == 0 &&
          header['SoTienConNo'] == 10000000 &&
          header['SoTienKhachDua'] == 0 &&
          header['TienThua'] == 0,
      'Đơn trả đủ không tiền thừa: xóa phiếu hoàn nợ đúng',
    );
    check(
      header['NgayTinhLai'] == sale && header['NgayHen'] == due,
      'Đơn chuyển sang ghi nợ: tự bổ sung ngày tính lãi/ngày hẹn',
    );
    check(await valid(header), 'Header có ngày công nợ thỏa validator');

    // C. Partially paid sale: deleting a repayment keeps cash = paid, no change.
    await put(
      'HoaDonBan',
      newSale(
        id: 'c',
        orderId: 103,
        total: 10000000,
        paid: 5000000,
        cash: 5000000,
        change: 0,
        dueAmount: 5000000,
        dueDate: DateTime.utc(2026, 11, 15),
        interestDate: sale,
        debtDatesVersion: 1,
      ),
    );
    await put('SoNo', {
      '_id': 'debt-c',
      'IdSoNo': 103,
      'IdHoaDon': 103,
      'SoTienDaTra': 5000000,
      'SoTienConNo': 5000000,
    });
    await addPayment(103, 'sale:c:payment', 3000000, sale);
    await addPayment(103, 'order-payment-c2', 2000000, sale);
    await service.payment(
      RecordKind.order,
      103,
      'order-payment-c2',
      null,
      requestId: token(),
    );
    header = await get('HoaDonBan', 'c');
    check(
      header['SoTienDaTra'] == 3000000 &&
          header['SoTienConNo'] == 7000000 &&
          header['SoTienKhachDua'] == 3000000 &&
          header['TienThua'] == 0,
      'Đơn trả một phần: xóa phiếu trả nợ cập nhật khách đưa = đã trả',
    );
    check(await valid(header), 'Đơn trả một phần vẫn thỏa validator');

    // D. Editing a paid-in-full sale with change into a credit sale.
    await put(
      'HoaDonBan',
      newSale(
        id: 'd',
        orderId: 104,
        total: 10000000,
        paid: 10000000,
        cash: 10020000,
        change: 20000,
        dueAmount: 0,
        debtDatesVersion: 1,
      ),
    );
    await put('SoNo', {
      '_id': 'debt-d',
      'IdSoNo': 104,
      'IdHoaDon': 104,
      'SoTienDaTra': 10000000,
      'SoTienConNo': 0,
    });
    await put('ChiTietHoaDonBan', {
      '_id': 'dline',
      'IdHoaDon': 104,
      'IdSanPham': 2,
      'SoLuong': 1,
      'DonGia': 10000000,
      'ThanhTien': 10000000,
    });
    await put('TonKhoPhuTung', {
      '_id': 'dstock',
      'IdSanPham': 2,
      'SoLuongTon': 10,
    });
    await addPayment(104, 'sale:d:payment', 10000000, sale);
    final edit = await service.load(RecordKind.order, 104);
    final lines = [
      for (final row in edit.lines)
        {...row, 'DonGia': row['_id'] == 'dline' ? 11000000 : row['DonGia']},
    ];
    await service.save(
      RecordKind.order,
      104,
      {...edit.header, 'GiamGia': 0},
      lines,
      requestId: token(),
    );
    header = await get('HoaDonBan', 'd');
    check(
      header['TongThanhToan'] == 11000000 &&
          header['SoTienDaTra'] == 10000000 &&
          header['SoTienConNo'] == 1000000 &&
          header['SoTienKhachDua'] == 10000000 &&
          header['TienThua'] == 0,
      'Sửa đơn tăng tổng tiền: tiền thừa về 0, khách đưa = đã trả',
    );
    check(
      header['NgayTinhLai'] == sale && header['NgayHen'] == due,
      'Sửa đơn phát sinh nợ: tự bổ sung ngày công nợ',
    );
    check(await valid(header), 'Đơn sau khi sửa thỏa validator');

    // E. Legacy sale (no version flags) keeps its previous behaviour.
    await put('HoaDonBan', {
      '_id': 'legacy',
      'IdHoaDon': 105,
      'IdKH': 1,
      'NgayMua': sale,
      'NgayTinhLai': sale,
      'NgayHen': due,
    });
    await put('SoNo', {
      '_id': 'debt-legacy',
      'IdSoNo': 105,
      'IdHoaDon': 105,
      'SoTienDaTra': 3000000,
      'SoTienConNo': 7000000,
    });
    await addPayment(105, 'legacy-pay', 3000000, sale);
    await service.payment(
      RecordKind.order,
      105,
      'legacy-pay',
      null,
      requestId: token(),
    );
    header = await get('HoaDonBan', 'legacy');
    check(
      header['SoTienDaTra'] == 0 &&
          header['SoTienConNo'] == 10000000 &&
          !header.containsKey('SoTienKhachDua'),
      'Đơn cũ vẫn xóa phiếu bình thường, không thêm trường mới',
    );

    // F. No pending plans or locks left behind.
    check(
      await db.collection('_record_changes').count({
            'State': {
              r'$in': ['pending', 'preparing'],
            },
          }) ==
          0,
      'Không còn kế hoạch thay đổi dang dở',
    );
    for (final name in ['HoaDonBan', 'SoNo', 'TraNo', 'TonKhoPhuTung']) {
      check(
        await db.collection(name).count({
              'SuaXoaDangLuu': {r'$exists': true},
            }) ==
            0,
        'Không còn khóa dang dở: $name',
      );
    }
    stdout.writeln('$checks checks passed.');
  } finally {
    await db.drop();
    await db.close();
  }
}
