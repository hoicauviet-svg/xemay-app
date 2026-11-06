import 'dart:convert';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'package:xemay_app/models/products/product_details.dart';
import 'package:xemay_app/models/batches/batch_models.dart';
import 'package:xemay_app/services/mongo_batch_repository.dart';
import 'package:xemay_app/models/sales/sale_models.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/models/finance/finance_models.dart';
import 'package:xemay_app/models/finance/opening_debt.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:xemay_app/models/directory/directory_models.dart';
import 'package:xemay_app/models/customers/customer_models.dart';
import 'package:xemay_app/models/services/service_models.dart';
import 'package:xemay_app/services/mongo_receipt_repository.dart';
import 'package:xemay_app/services/mongo_product_details_repository.dart';
import 'package:xemay_app/services/mongo_sales_repository.dart';
import 'package:xemay_app/services/mongo_order_repository.dart';
import 'package:xemay_app/services/mongo_pawn_repository.dart';
import 'package:xemay_app/services/mongo_finance_repository.dart';
import 'package:xemay_app/services/mongo_opening_debt_repository.dart';
import 'package:xemay_app/services/mongo_reports_repository.dart';
import 'package:xemay_app/services/mongo_directory_repository.dart';
import 'package:xemay_app/services/mongo_customer_repository.dart';
import 'package:xemay_app/services/mongo_service_repository.dart';

final results = <Map<String, dynamic>>[];
void eq(String id, dynamic actual, dynamic expected) {
  final ok = actual == expected;
  results.add({
    'case': id,
    'actual': actual,
    'expected': expected,
    'passed': ok,
  });
  stdout.writeln('${ok ? 'PASS' : 'FAIL'} $id: $actual / $expected');
}

String key() => ObjectId().oid;
Future<void> main() async {
  final name = 'QA_FULL_chain_${DateTime.now().microsecondsSinceEpoch}',
      uri = 'mongodb://127.0.0.1:27017/$name';
  final db = Db(uri);
  await db.open();
  final out = Directory('test-results/full-2026-11-05/chain')
    ..createSync(recursive: true);
  File('${out.path}/database.txt').writeAsStringSync(name);
  final receipts = MongoReceiptRepository(uri: uri),
      batches = MongoBatchRepository(uri: uri),
      costs = MongoProductDetailsRepository(uri: uri),
      sales = MongoSalesRepository(uri: uri),
      orders = MongoOrderRepository(uri: uri),
      pawns = MongoPawnRepository(uri: uri),
      finance = MongoFinanceRepository(uri: uri),
      old = MongoOpeningDebtRepository(uri: uri),
      reports = MongoReportsRepository(uri: uri),
      dirs = MongoDirectoryRepository(uri: uri),
      customers = MongoCustomerRepository(uri: uri),
      services = MongoServiceRepository(uri: uri);
  final d0 = DateTime.utc(2026, 10, 6),
      d30 = DateTime.utc(2026, 11, 5),
      d45 = DateTime.utc(2026, 11, 20);
  try {
    final schema = await Process.run(
      '/private/tmp/xemay-db-build-env/bin/python',
      ['../upgrade_receipt_costs.py', '--database', name, '--apply'],
    );
    if (schema.exitCode != 0) throw StateError(schema.stderr.toString());
    final migration = await Process.run(
      '/private/tmp/xemay-db-build-env/bin/python',
      [
        '-c',
        'from upgrade_sales_schema import upgrade; import sys; upgrade(sys.argv[1], True, sys.argv[2])',
        name,
        out.absolute.path,
      ],
      workingDirectory: '..',
    );
    if (migration.exitCode != 0) throw StateError(migration.stderr.toString());
    final kh = CustomerDraft()
      ..name = 'QA_FULL_CHAIN_KH'
      ..phone = '0900110509'
      ..address = 'Dia chi QA';
    await customers.create(kh);
    final khid =
        (await customers.fetch(search: kh.name)).rows.single['IdKH'] as int;
    final supplier = await dirs.create(
      DirectoryEntryDraft(DirectoryKind.partner)
        ..name = 'QA_FULL_CHAIN_NCC'
        ..phone = '0900110508'
        ..address = 'QA Address'
        ..taxCode = 'QA123'
        ..representative = 'QA Rep',
    );
    final carrier = await dirs.create(
      DirectoryEntryDraft(DirectoryKind.carrier)
        ..name = 'QA_FULL_CHAIN_VC'
        ..phone = '0900110507'
        ..plate = 'QA-001'
        ..notes = 'QA',
    );
    final service = await services.create(
      ServiceDraft()
        ..name = 'QA_FULL_CHAIN_DV'
        ..price = '150000'
        ..description = 'QA Service',
    );
    ReceiptLine line(String n, int price, {int qty = 1, int? sale}) =>
        ReceiptLine(
          name: n,
          quantity: qty,
          unitPrice: price,
          frameNumber: '$n-FRAME',
          engineNumber: '$n-ENGINE',
          plate: 'QA-$n',
          salePrice: sale,
        );
    Future<int> receive(
      ReceiptProductType type,
      ReceiptMode mode,
      List<ReceiptLine> lines,
      int paid,
    ) async {
      final token = key(),
          total = lines.fold<int>(0, (s, l) => s + l.amount),
          qty = lines.fold<int>(0, (s, l) => s + l.quantity);
      final draft = ReceiptPreview(
        type: type,
        mode: mode,
        date: d0,
        partner: supplier.name,
        partnerId: supplier.id,
        carrier: carrier.name,
        carrierId: carrier.id,
        notes: 'QA chain',
        paidAmount: paid,
        lines: lines,
        batchInfo: mode == ReceiptMode.batch
            ? BatchReceiptInfo(
                quantity: qty,
                totalAmount: total,
                deliveredBy: carrier.name,
                origin: supplier.name,
                date: d0,
                paidAmount: paid,
                partnerId: supplier.id,
                carrierId: carrier.id,
              )
            : null,
      );
      await receipts.save(draft, token);
      await receipts.save(draft, token);
      final h = (await db.collection('NhapHang').findOne({'_id': '$token-h'}))!;
      eq('receipt $type $mode total', h['SoTien'], total);
      eq('receipt $type $mode debt', h['SoTienConNo'], total - paid);
      return h['IdNhapHang'] as int;
    }

    await receive(ReceiptProductType.newVehicle, ReceiptMode.batch, [
      line('N1', 20000000, sale: 25000000),
      line('N2', 20000000, sale: 25000000),
    ], 10000000);
    await receive(ReceiptProductType.usedVehicle, ReceiptMode.batch, [
      line('U1', 10000000, sale: 13000000),
    ], 10000000);
    await receive(ReceiptProductType.part, ReceiptMode.batch, [
      line('P1', 100000, qty: 10, sale: 150000),
    ], 1000000);
    for (final t in ReceiptProductType.values) {
      await receive(t, ReceiptMode.single, [
        line(
          'SINGLE_${t.name}',
          100000,
          qty: t.isVehicle ? 1 : 2,
          sale: 150000,
        ),
      ], t.isVehicle ? 100000 : 200000);
    }
    final n1 = (await db.collection('Xe').findOne({'TenXe': 'N1'}))!,
        p1 = (await db.collection('SanPham').findOne({'TenSanPham': 'P1'}))!;
    final ref = ProductReference(id: n1['IdXe'] as int, vehicle: true);
    for (final amount in [200000, 300000]) {
      final token = key();
      await costs.addCost(
        ref,
        date: d0,
        amount: amount,
        notes: 'QA cost',
        requestId: token,
      );
      await costs.addCost(
        ref,
        date: d0,
        amount: amount,
        notes: 'QA cost',
        requestId: token,
      );
    }
    eq('N1 total costs', (await costs.load(ref)).totalCosts, 500000);
    final sale = SaleDraft(
      lines: [
        SaleLine(
          kind: 'xe',
          name: 'N1',
          quantity: 1,
          price: 25000000,
          productId: n1['IdSanPham'] as int,
          vehicleId: n1['IdXe'] as int,
        ),
        SaleLine(
          kind: 'phu_tung',
          name: 'P1',
          quantity: 2,
          price: 150000,
          productId: p1['IdSanPham'] as int,
        ),
        SaleLine(
          kind: 'dich_vu',
          name: service.name,
          quantity: 1,
          price: 150000,
          serviceId: service.id,
        ),
      ],
      date: d0,
      discount: 450000,
      paid: 10000000,
      customerId: khid,
      paymentDueDate: d30,
      interestDate: d0,
    );
    final token = key(), saved = await sales.save(sale, token);
    eq(
      'sale duplicate ID',
      (await sales.save(sale, token)).invoiceId,
      saved.invoiceId,
    );
    var order = await orders.load(saved.invoiceId);
    eq('sale goods', order.goodsTotal, 25450000);
    eq('sale total', order.total, 25000000);
    eq('sale debt', order.due, 15000000);
    eq('sale 30 day interest', order.interestAt(d30), 300000);
    eq(
      'part stock',
      (await db.collection('TonKhoPhuTung').findOne({
        'IdSanPham': p1['IdSanPham'],
      }))?['SoLuongTon'],
      8,
    );
    var data = await reports.load(ReportRange());
    eq(
      'report sales goods',
      data.sections[ReportKind.sales]!.totals['Tiền hàng'],
      25450000,
    );
    eq(
      'report sales profit',
      data.sections[ReportKind.sales]!.totals['Lợi nhuận'],
      4300000,
    );
    eq(
      'report customer debt',
      data.sections[ReportKind.customerDebt]!.totals['Còn nợ'],
      15000000,
    );
    File('${out.path}/before-repayment.json').writeAsStringSync(
      jsonEncode({
        for (final e in data.sections.entries)
          e.key.name: {
            'rows': e.value.rows
                .map(
                  (r) => r
                      .map((v) => v is DateTime ? v.toIso8601String() : v)
                      .toList(),
                )
                .toList(),
            'totals': e.value.totals,
          },
      }),
    );
    final batch = (await db.collection('NhapHang').findOne({
      'SoTien': 40000000,
    }))!;
    for (final amount in [5000000, 25000000]) {
      final request = key();
      final payment = BatchPaymentPreview(
        batchId: batch['IdNhapHang'] as int,
        amount: amount,
        date: d30,
        notes: 'QA supplier repay',
      );
      await batches.pay(payment, requestId: request);
      await batches.pay(payment, requestId: request);
    }
    eq(
      'supplier remaining',
      (await batches.findById(batch['IdNhapHang'] as int))!.remaining,
      0,
    );
    eq(
      'supplier history count',
      (await batches.payments(batch['IdNhapHang'] as int)).length,
      3,
    );
    await db
        .collection('TonKhoPhuTung')
        .updateOne(
          {'IdSanPham': p1['IdSanPham']},
          {
            r'$set': {'GiaVonThamKhao': 200000},
          },
        );
    eq(
      'profit keeps recorded purchase cost after reference changes',
      (await reports.load(
        ReportRange(),
      )).sections[ReportKind.sales]!.totals['Lợi nhuận'],
      4300000,
    );
    await orders.pay(
      saved.invoiceId,
      date: d30,
      amount: 5000000,
      notes: 'QA repay1',
      requestId: key(),
      nextAppointment: d45,
    );
    order = await orders.load(saved.invoiceId);
    eq('order after partial debt', order.due, 10000000);
    eq('order next interest', order.interestAt(d45), 100000);
    await orders.pay(
      saved.invoiceId,
      date: d45,
      amount: 10000000,
      notes: 'QA repay2',
      requestId: key(),
    );
    eq('order full debt', (await orders.load(saved.invoiceId)).due, 0);
    for (final daily in [false, true]) {
      final draft = PawnDraft()
        ..customerId = khid
        ..asset = 'QA pawn $daily'
        ..amount = daily ? '3500000' : '10000000'
        ..rate = daily ? '2000' : '2'
        ..daily = daily
        ..loanDate = d0
        ..dueDate = d30;
      final id = await pawns.create(draft, requestId: key()),
          date = daily ? d0.add(const Duration(days: 10)) : d30;
      var detail = await pawns.details(id);
      eq(
        'pawn initial interest daily=$daily',
        detail.interestAccrualAt(date)?.roundedAmount,
        daily ? 70000 : 200000,
      );
      await pawns.pay(
        PawnPaymentDraft(
          pawnId: id,
          date: date,
          principal: daily ? 3500000 : 2000000,
          interest: daily ? 70000 : 200000,
          collectedInterest: daily ? 70000 : 200000,
          appointmentDate: d45,
        ),
        requestId: key(),
      );
      detail = await pawns.details(id);
      eq('pawn remaining daily=$daily', detail.remaining, daily ? 0 : 8000000);
      if (!daily) {
        eq(
          'pawn next interest',
          detail.interestAccrualAt(d45)?.roundedAmount,
          80000,
        );
        await pawns.pay(
          PawnPaymentDraft(
            pawnId: id,
            date: d45,
            principal: 8000000,
            interest: 80000,
            collectedInterest: 80000,
          ),
          requestId: key(),
        );
      }
      eq('pawn settled', (await pawns.details(id)).contract['TrangThai'], true);
    }
    final loanid = await finance.createLoan(
      FundingLoanDraft()
        ..amount = '20000000'
        ..partner = 'QA lender'
        ..rate = '1.5'
        ..date = d0
        ..dueDate = d30,
      requestId: key(),
    );
    eq(
      'funding 30day interest',
      (await finance.loanDetails(loanid)).interestAt(d30),
      300000,
    );
    await finance.repay(
      FundingPaymentDraft(
        loanId: loanid,
        date: d30,
        principal: 5000000,
        interest: 300000,
      ),
      requestId: key(),
    );
    eq('funding debt', (await finance.loanDetails(loanid)).remaining, 15000000);
    eq(
      'funding next interest',
      (await finance.loanDetails(loanid)).interestAt(d45),
      112500,
    );
    await finance.repay(
      FundingPaymentDraft(
        loanId: loanid,
        date: d45,
        principal: 15000000,
        interest: 112500,
      ),
      requestId: key(),
    );
    eq('funding settled', (await finance.loanDetails(loanid)).remaining, 0);
    await db.collection('NoCu').insertOne({
      'Id': 1,
      'IdKH': '$khid',
      'NgayNo': d0,
      'TongNo': 1000000.0,
      'SoTienDaTra': 0.0,
      'SoCoNo': 1000000.0,
    });
    for (final amount in [300000, 700000]) {
      await old.pay(
        OpeningDebtPayment(
          debtId: 1,
          date: d30,
          principal: amount,
          interest: 0,
          collectedInterest: 0,
        ),
        requestId: key(),
      );
    }
    eq('old debt settled', (await old.details(1)).remaining, 0);
    for (final income in [true, false]) {
      await finance.createCash(
        CashEntryDraft()
          ..date = d30
          ..income = income
          ..reason = 'QA manual $income'
          ..amount = income ? '500000' : '200000',
        requestId: key(),
      );
    }
    data = await reports.load(ReportRange());
    eq(
      'supplier report cleared',
      data.sections[ReportKind.supplierDebt]!.totals['Còn nợ'],
      0,
    );
    eq(
      'supplier payments with initial',
      data.sections[ReportKind.supplierRepayments]!.totals['Số tiền trả'],
      51400000,
    );
    for (final label in [
      'Tiền hàng',
      'Giảm giá',
      'Doanh thu',
      'Đã thu',
      'Còn nợ',
      'Chi phí',
      'Giá nhập',
      'Lợi nhuận',
    ]) {
      final values = [
        for (final e in data.salesByGroup.entries)
          if (e.key != ReportProductGroup.all) e.value.totals[label],
      ];
      eq(
        'sales group sum $label',
        values.every((v) => v is num)
            ? values.cast<num>().fold<num>(0, (a, b) => a + b)
            : null,
        data.sections[ReportKind.sales]!.totals[label],
      );
    }
    eq(
      'report repaid order principal',
      data.sections[ReportKind.customerRepayments]!.totals['Tiền trả nợ'],
      25000000,
    );
    eq(
      'report order collected interest',
      data.sections[ReportKind.customerRepayments]!.totals['Lãi thực thu'],
      400000,
    );
    eq(
      'report pawn collected principal',
      data.sections[ReportKind.pawnCollections]!.totals['Gốc đã thu'],
      13500000,
    );
    eq(
      'report pawn collected interest',
      data.sections[ReportKind.pawnCollections]!.totals['Lãi thực thu'],
      350000,
    );
    eq(
      'report funding paid principal',
      data.sections[ReportKind.fundingRepayments]!.totals['Trả gốc'],
      20000000,
    );
    eq(
      'report funding paid interest',
      data.sections[ReportKind.fundingRepayments]!.totals['Trả lãi'],
      412500,
    );
    eq(
      'report old principal',
      data.sections[ReportKind.oldDebtRepayments]!.totals['Tiền trả nợ'],
      1000000,
    );
    eq(
      'report cash income',
      data.sections[ReportKind.cash]!.totals['Thu'],
      900000,
    );
    eq(
      'report cash expense',
      data.sections[ReportKind.cash]!.totals['Chi'],
      700000,
    );
    eq(
      'report customer cleared',
      data.sections[ReportKind.customerDebt]!.totals['Còn nợ'],
      0,
    );
    File('${out.path}/after-repayment.json').writeAsStringSync(
      jsonEncode({
        for (final e in data.sections.entries)
          e.key.name: {
            'rows': e.value.rows
                .map(
                  (r) => r
                      .map((v) => v is DateTime ? v.toIso8601String() : v)
                      .toList(),
                )
                .toList(),
            'totals': e.value.totals,
          },
      }),
    );
  } catch (e, st) {
    results.add({
      'case': 'UNHANDLED',
      'passed': false,
      'error': '$e',
      'stack': '$st',
    });
    stderr.writeln('$e\n$st');
  } finally {
    File('${out.path}/results.json').writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'database': name, 'results': results}),
    );
    for (final close in [
      receipts.close,
      batches.close,
      costs.close,
      sales.close,
      orders.close,
      pawns.close,
      finance.close,
      old.close,
      reports.close,
      dirs.close,
      customers.close,
      services.close,
    ]) {
      await close();
    }
    await db.close();
  }
  if (results.any((r) => r['passed'] != true)) exitCode = 1;
}
