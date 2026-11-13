import '../finance/cash_category.dart';
import '../orders/order_details.dart';
import '../finance/finance_models.dart';

class ReportRange {
  ReportRange({DateTime? from, DateTime? to})
    : from = from == null ? null : financeDay(from),
      to = to == null ? null : financeDay(to) {
    if (this.from != null && this.to != null && this.from!.isAfter(this.to!)) {
      throw ArgumentError('Ngày bắt đầu không được sau ngày kết thúc.');
    }
  }
  final DateTime? from, to;
  Map<String, dynamic> filter(String field) => {
    if (from != null || to != null)
      field: {
        if (from != null) r'$gte': from,
        if (to != null) r'$lt': to!.add(const Duration(days: 1)),
      },
  };
  bool contains(dynamic date) {
    if (date is! DateTime) return from == null && to == null;
    final d = financeDay(date);
    return (from == null || !d.isBefore(from!)) &&
        (to == null || !d.isAfter(to!));
  }
}

enum ReportKind {
  overview('Tổng quan'),
  sales('Bán hàng'),
  receipts('Nhập hàng'),
  stock('Tồn kho'),
  debts('Công nợ'),
  cash('Thu chi'),
  pawn('Cầm đồ'),
  pawnDebt('Dư nợ cầm đồ'),
  pawnCollections('Thu nợ cầm đồ'),
  customerDebt('Khách hàng nợ'),
  supplierDebt('Nợ nhà cung cấp'),
  customerRepayments('Khách hàng trả nợ'),
  supplierRepayments('Trả nợ nhà cung cấp'),
  oldDebtRepayments('Khách trả nợ cũ'),
  fundingRepayments('Trả nợ vay vốn');

  const ReportKind(this.label);
  final String label;
  bool get current =>
      this == stock ||
      this == debts ||
      this == pawnDebt ||
      this == customerDebt ||
      this == supplierDebt;
}

enum ReportProductGroup {
  all('Tất cả'),
  newVehicles('Xe mới'),
  usedVehicles('Xe cũ'),
  parts('Phụ tùng'),
  services('Dịch vụ'),
  unknown('Chưa phân loại');

  const ReportProductGroup(this.label);
  final String label;
}

class ReportColumn {
  const ReportColumn(this.label, {this.money = false, this.width = 150});
  final String label;
  final bool money;
  final double width;
}

class ReportSection {
  const ReportSection({
    required this.columns,
    required this.rows,
    required this.totals,
    this.notes = const [],
  });
  final List<ReportColumn> columns;
  final List<List<dynamic>> rows;
  final Map<String, num?> totals;
  final List<String> notes;
}

class ReportDebtAging {
  const ReportDebtAging({this.within = 0, this.overdue = 0, this.undated = 0});
  final num? within, overdue, undated;
}

class ReportsData {
  const ReportsData(
    this.sections,
    this.loadedAt, {
    this.salesByGroup = const {},
    this.receiptsByGroup = const {},
    this.customerAging = const ReportDebtAging(),
    this.pawnAging = const ReportDebtAging(),
    this.cashflow = const ReportCashflow(),
  });
  final Map<ReportKind, ReportSection> sections;
  final DateTime loadedAt;
  final Map<ReportProductGroup, ReportSection> salesByGroup, receiptsByGroup;
  final ReportDebtAging customerAging, pawnAging;
  final ReportCashflow cashflow;
}

class ReportCashflow {
  const ReportCashflow({this.income = const {}, this.expense = const {}});
  final Map<String, num?> income, expense;
  num? get totalIncome => _sumValues(income.values);
  num? get totalExpense => _sumValues(expense.values);
  num? get balance {
    final income = totalIncome, expense = totalExpense;
    return income == null || expense == null ? null : income - expense;
  }
}

/// An unknown component keeps the total unknown instead of treating it as zero.
class _Sum {
  num value = 0;
  int missing = 0;
  void add(dynamic amount) {
    if (amount is num && amount.isFinite) {
      value += amount;
    } else {
      missing++;
    }
  }

  num? get total => missing == 0 ? value : null;
}

List<List<dynamic>> _sortVouchers(List<List<dynamic>> rows) {
  rows.sort((a, b) {
    final ad = a[1], bd = b[1];
    if (ad is DateTime && bd is DateTime) {
      final result = bd.compareTo(ad);
      if (result != 0) return result;
    } else if (ad is DateTime) {
      return -1;
    } else if (bd is DateTime) {
      return 1;
    }
    final ai = a[0], bi = b[0];
    if (ai is num && bi is num) return bi.compareTo(ai);
    return '${bi ?? ''}'.compareTo('${ai ?? ''}');
  });
  return rows;
}

num? _number(dynamic value) => value is num && value.isFinite ? value : null;
num? _sumValues(Iterable<dynamic> values) {
  final sum = _Sum();
  for (final v in values) {
    sum.add(v);
  }
  return sum.total;
}

class ReportCalculator {
  static ReportDebtAging debtAging(
    Iterable<Map<String, dynamic>> rows, {
    required String amountKey,
    required String dateKey,
    required DateTime today,
    bool includeUnknownAmounts = false,
  }) {
    final within = _Sum(), overdue = _Sum(), undated = _Sum();
    for (final row in rows) {
      final amount = _number(row[amountKey]);
      if ((amount == null && !includeUnknownAmounts) ||
          (amount != null && amount <= 0)) {
        continue;
      }
      final date = row[dateKey];
      if (date is! DateTime) {
        undated.add(amount);
      } else if (financeDay(date).isBefore(financeDay(today))) {
        overdue.add(amount);
      } else {
        within.add(amount);
      }
    }
    return ReportDebtAging(
      within: within.total,
      overdue: overdue.total,
      undated: undated.total,
    );
  }

  static ReportSection cashCategoryTotals(ReportSection source) {
    final buckets = <String, Map<String, _Sum>>{};
    for (final row in source.rows) {
      final category = row.length > 5 && row[5] is String
          ? row[5] as String
          : row[2] == 'Thu'
          ? 'Thu khác'
          : 'Chi khác';
      final totals = buckets.putIfAbsent(
        category,
        () => {'Thu': _Sum(), 'Chi': _Sum()},
      );
      if (row[2] == 'Thu' || row[2] == 'Chi') totals[row[2]]!.add(row[4]);
    }
    final names = buckets.keys.toList()..sort();
    return ReportSection(
      columns: const [
        ReportColumn('Danh mục', width: 360),
        ReportColumn('Thu', money: true, width: 220),
        ReportColumn('Chi', money: true, width: 220),
      ],
      rows: [
        for (final name in names)
          [name, buckets[name]!['Thu']!.total, buckets[name]!['Chi']!.total],
      ],
      totals: source.totals,
      notes: source.notes,
    );
  }

  static ReportSection filterCash(
    ReportSection source,
    String type, {
    String? category,
  }) {
    if (!['all', 'income', 'expense'].contains(type)) {
      throw ArgumentError.value(type);
    }
    if (type == 'all' && category == null) return source;
    final income = type == 'income';
    final rows = source.rows
        .where(
          (r) =>
              (type == 'all' || r[2] == (income ? 'Thu' : 'Chi')) &&
              (category == null || (r.length > 5 && r[5] == category)),
        )
        .toList();
    return ReportSection(
      columns: source.columns,
      rows: rows,
      totals: {
        'Thu': _sumValues(rows.where((r) => r[2] == 'Thu').map((r) => r[4])),
        'Chi': _sumValues(rows.where((r) => r[2] == 'Chi').map((r) => r[4])),
      },
      notes: [
        ...source.notes.where(
          (n) => !n.endsWith('phiếu chưa xác định Thu hay Chi.'),
        ),
        if (type != 'all') 'Loại phiếu: ${income ? 'Thu' : 'Chi'}.',
        if (category != null) 'Danh mục: $category',
      ],
    );
  }

  static ReportSection filterDebtDetail(ReportSection source, String search) {
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return source;
    final rows = source.rows
        .where(
          (row) => row
              .take(5)
              .any(
                (value) =>
                    value != null && '$value'.toLowerCase().contains(term),
              ),
        )
        .toList();
    return ReportSection(
      columns: source.columns,
      rows: rows,
      totals: {
        for (final index in [5, 6, 7])
          source.columns[index].label: _sumValues(rows.map((r) => r[index])),
      },
      notes: [...source.notes, 'Tìm kiếm: ${search.trim()}'],
    );
  }

  static Map<ReportProductGroup, num?> _allocate(
    num? amount,
    Map<ReportProductGroup, num?> weights,
  ) {
    final sum = _sumValues(weights.values);
    if (amount == null ||
        amount < 0 ||
        sum == null ||
        sum <= 0 ||
        weights.values.any((v) => v! < 0)) {
      return {for (final key in weights.keys) key: amount == 0 ? 0 : null};
    }
    final raw = {
      for (final entry in weights.entries)
        entry.key: amount * entry.value! / sum,
    };
    if (amount % 1 != 0) return raw;
    final result = {
      for (final entry in raw.entries) entry.key: entry.value.floor() as num,
    };
    var remainder =
        amount.toInt() - result.values.fold<num>(0, (s, v) => s + v).toInt();
    final keys = raw.keys.toList()
      ..sort((a, b) => (raw[b]! - result[b]!).compareTo(raw[a]! - result[a]!));
    for (final key in keys) {
      if (remainder-- <= 0) break;
      result[key] = result[key]! + 1;
    }
    return result;
  }

  static ReportsData build({
    required ReportRange range,
    required Map<String, List<Map<String, dynamic>>> source,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final today = financeDay(timestamp);
    List<Map<String, dynamic>> table(String name) => source[name] ?? [];
    final partners = {for (final row in table('DoiTac')) '${row['_id']}': row};
    final carriers = {
      for (final row in table('VanChuyen')) '${row['_id']}': row,
    };
    dynamic directoryName(
      Map<String, dynamic>? record,
      String key,
      dynamic fallback,
    ) {
      final name = record?[key]?.toString().trim();
      return name != null && name.isNotEmpty ? name : fallback;
    }

    final vehicles = {for (final v in table('Xe')) v['IdXe']: v};
    final customers = {
      for (final row in table('KhachHang')) '${row['IdKH']}': row,
    };
    final products = {
      for (final row in table('SanPham')) row['IdSanPham']: row,
    };
    final services = {for (final row in table('DichVu')) '${row['_id']}': row};
    ReportProductGroup classify(Map<String, dynamic> line) {
      final kind = line['LoaiSanPham'];
      if (kind == 'dich_vu' || line['IdDichVu'] != null) {
        return ReportProductGroup.services;
      }
      final condition =
          vehicles[line['IdXe']]?['TinhTrangXe'] ?? line['TinhTrangXe'];
      if (condition == 'moi' || kind == 'xe_moi') {
        return ReportProductGroup.newVehicles;
      }
      if (condition == 'cu' || kind == 'xe_cu') {
        return ReportProductGroup.usedVehicles;
      }
      if (line['IdXe'] == null &&
          (kind == 'phu_tung' ||
              products[line['IdSanPham']]?['LoaiSanPham'] == 'phu_tung')) {
        return ReportProductGroup.parts;
      }
      return ReportProductGroup.unknown;
    }

    final groupedSales = <ReportProductGroup, List<List<dynamic>>>{};
    final groupedReceipts = <ReportProductGroup, List<List<dynamic>>>{};
    num? recordedCosts(Map<String, dynamic> record) {
      final entries = record['ChiPhi'];
      if (entries is List) {
        return _sumValues(
          entries
              .where((c) => c is! Map || c['DaXoa'] != true)
              .map((c) => c is Map ? c['SoTien'] : null),
        );
      }
      return record.containsKey('TongChiPhi')
          ? _number(record['TongChiPhi'])
          : 0;
    }

    final vehicleReceipts = <dynamic, List<Map<String, dynamic>>>{};
    for (final row in table('ChiTietNhapHang')) {
      if (row['IdXe'] != null)
        vehicleReceipts.putIfAbsent(row['IdXe'], () => []).add(row);
    }
    Map<String, dynamic>? receiptFor(dynamic id) {
      final rows = vehicleReceipts[id] ?? [];
      return rows.length == 1 ? rows.single : null;
    }

    final partCosts = <dynamic, List<num?>>{};
    for (final row in table('ChiTietNhapHang')) {
      if (row['IdXe'] == null) {
        partCosts
            .putIfAbsent(row['IdSanPham'], () => [])
            .add(recordedCosts(row));
      }
    }
    final receiptHeaders = {
      for (final row in table('NhapHang')) row['IdNhapHang']: row,
    };
    final partReceipts = <dynamic, List<Map<String, dynamic>>>{};
    for (final row in table('ChiTietNhapHang')) {
      if (row['IdXe'] == null) {
        partReceipts.putIfAbsent(row['IdSanPham'], () => []).add(row);
      }
    }
    num? historicalPartPrice(Map<String, dynamic> line, dynamic soldAt) {
      if (soldAt is! DateTime) return null;
      final quantity = _number(line['SoLuong']);
      if (quantity == null || quantity <= 0) return null;
      final prices = <num>{};
      num received = 0;
      for (final receipt
          in partReceipts[line['IdSanPham']] ?? <Map<String, dynamic>>[]) {
        final header = receiptHeaders[receipt['IdNhapHang']];
        if (header?['TrangThaiLuu'] == 'dang_luu') continue;
        final date = header?['NgayNhap'];
        if (date is! DateTime) return null;
        if (financeDay(date).isAfter(financeDay(soldAt))) continue;
        final price = _number(receipt['GiaNhap']);
        final count = _number(receipt['SoLuong']);
        if (price == null || price < 0 || count == null || count <= 0)
          return null;
        prices.add(price);
        received += count;
      }
      // A changing purchase price requires a saved sale cost/allocation; never
      // choose the latest stock reference price for an old sale.
      return prices.length == 1 && received >= quantity ? prices.single : null;
    }

    num? saleCosts(List<Map<String, dynamic>> details) {
      if (details.isEmpty) return null;
      final values = <num?>[];
      final seen = <dynamic>{};
      for (final line in details) {
        if (line['LoaiSanPham'] == 'dich_vu' || line['IdDichVu'] != null) {
          continue;
        }
        if (line['IdXe'] != null) {
          if (!seen.add(line['IdXe'])) continue;
          final vehicle = vehicles[line['IdXe']];
          final receipt = receiptFor(line['IdXe']);
          values.add(
            vehicle == null
                ? (receipt == null ? null : recordedCosts(receipt))
                : vehicle.containsKey('ChiPhi') ||
                      vehicle.containsKey('TongChiPhi') ||
                      receipt == null
                ? recordedCosts(vehicle)
                : recordedCosts(receipt),
          );
        } else {
          final product = products[line['IdSanPham']];
          final costs = product == null
              ? null
              : _sumValues([
                  recordedCosts(product),
                  ...partCosts[line['IdSanPham']] ?? <num?>[],
                ]);
          // Shared part expenses have no link to a particular sale in the source.
          values.add(costs == 0 ? 0 : null);
        }
      }
      return _sumValues(values);
    }

    num? salePurchaseCost(List<Map<String, dynamic>> details) {
      if (details.isEmpty) return null;
      final values = <num?>[];
      final seen = <dynamic>{};
      for (final line in details) {
        if (line['LoaiSanPham'] == 'dich_vu' || line['IdDichVu'] != null) {
          // A missing service cost stays zero, including old invoices.
          final recorded = _number(line['GiaNhap']);
          final quantity = _number(line['SoLuong']);
          values.add(
            recorded == null || recorded < 0
                ? 0
                : recorded * (quantity == null || quantity <= 0 ? 1 : quantity),
          );
          continue;
        }
        final quantity = _number(line['SoLuong']);
        if (quantity == null || quantity <= 0) return null;
        num? price;
        if (line['IdXe'] != null) {
          if (quantity != 1 || !seen.add(line['IdXe'])) return null;
          price =
              _number(line['GiaNhap']) ??
              _number(vehicles[line['IdXe']]?['GiaNhap']) ??
              _number(receiptFor(line['IdXe'])?['GiaNhap']);
        } else {
          // Current reference prices do not establish historical sale costs.
          price = _number(line['GiaNhap']);
        }
        values.add(price == null || price < 0 ? null : price * quantity);
      }
      return _sumValues(values);
    }

    String lineName(Map<String, dynamic> line) {
      final values = [
        line['TenSanPham'],
        vehicles[line['IdXe']]?['TenXe'],
        products[line['IdSanPham']]?['TenSanPham'],
        services['${line['IdDichVu']}']?['TenDichVu'],
      ];
      final name = values
          .where((v) => v != null && '$v'.trim().isNotEmpty)
          .firstOrNull;
      if (name == null) return '';
      final quantity = _number(line['SoLuong']);
      final count = quantity == null
          ? ''
          : ' × ${quantity % 1 == 0 ? quantity.toInt() : quantity}';
      return '${line['LoaiSanPham'] == 'dich_vu' ? 'Dịch vụ: ' : ''}$name$count';
    }

    final lines = <dynamic, List<Map<String, dynamic>>>{};
    for (final line in table('ChiTietHoaDonBan')) {
      lines.putIfAbsent(line['IdHoaDon'], () => []).add(line);
    }
    final debts = <dynamic, List<Map<String, dynamic>>>{};
    for (final row in table('SoNo')) {
      debts.putIfAbsent(row['IdHoaDon'], () => []).add(row);
    }
    final orders = table(
      'HoaDonBan',
    ).where((r) => r['TrangThaiLuu'] != 'dang_luu').toList();
    final periodOrders = orders.where((r) => range.contains(r['NgayMua']));
    final salesRows = <List<dynamic>>[],
        salesSums = List.generate(9, (_) => _Sum());
    var missingSales = 0;
    final salesMismatchIds = <dynamic>[];
    OrderDetails detailsFor(Map<String, dynamic> header) {
      final legacy = header['PhienBanBanHang'] == null;
      final detailLines = [
        for (final line
            in lines[header['IdHoaDon']] ?? <Map<String, dynamic>>[])
          {
            ...line,
            if (line['GiaNhap'] == null &&
                line['IdXe'] == null &&
                line['LoaiSanPham'] != 'dich_vu' &&
                line['IdDichVu'] == null)
              'GiaNhap': historicalPartPrice(line, header['NgayMua']),
            'DonGiaHienThi':
                line['DonGia'] ??
                (legacy
                    ? (line['DonGiaNguon'] ?? vehicles[line['IdXe']]?['GiaBan'])
                    : null),
          },
      ];
      if (legacy && detailLines.isEmpty && vehicles[header['IdXe']] != null) {
        detailLines.add({
          'IdXe': header['IdXe'],
          'IdSanPham': header['IdSanPham'],
          'SoLuong': 1,
          'DonGiaHienThi': vehicles[header['IdXe']]!['GiaBan'],
        });
      }
      return OrderDetails(
        header: header,
        customer: null,
        lines: detailLines,
        debts: debts[header['IdHoaDon']] ?? [],
        payments: [],
      );
    }

    for (final header in periodOrders) {
      final order = detailsFor(header);
      final detailLines = order.lines;
      final costs = saleCosts(detailLines);
      final purchase = salePurchaseCost(detailLines);
      final profit = order.total == null || purchase == null || costs == null
          ? null
          : order.total! - purchase - costs;
      final values = <dynamic>[
        1,
        order.goodsTotal,
        order.discount,
        order.total,
        order.paid,
        order.due,
        costs,
        purchase,
        profit,
      ];
      if (values.any((v) => _number(v) == null)) missingSales++;
      if (order.total != null &&
          order.paid != null &&
          order.due != null &&
          (order.total! - order.paid! - order.due!).abs() > 0.01) {
        salesMismatchIds.add(header['IdHoaDon']);
      }
      detailLines.sort(
        (a, b) =>
            ((_number(a['DongSo']) ?? 0)).compareTo(_number(b['DongSo']) ?? 0),
      );
      final names = detailLines
          .map(lineName)
          .where((name) => name.isNotEmpty)
          .join('\n');
      salesRows.add([
        header['IdHoaDon'],
        header['NgayMua'],
        customers['${header['IdKH']}']?['TenKhachHang'],
        names,
        ...values.skip(1),
      ]);
      for (var i = 0; i < values.length; i++) {
        salesSums[i].add(values[i]);
      }
      final groups = <ReportProductGroup, List<Map<String, dynamic>>>{};
      for (final line in detailLines) {
        groups.putIfAbsent(classify(line), () => []).add(line);
      }
      final weights = {
        for (final entry in groups.entries)
          entry.key: _sumValues(
            entry.value.map((line) {
              final price = OrderDetails.unitPrice(line),
                  quantity = _number(line['SoLuong']);
              return price == null || quantity == null
                  ? null
                  : price * quantity;
            }),
          ),
      };
      final reconciled =
          order.goodsTotal != null &&
          _sumValues(weights.values) != null &&
          (_sumValues(weights.values)! - order.goodsTotal!).abs() < .01;
      final discounts = _allocate(reconciled ? order.discount : null, weights);
      final netReconciled =
          reconciled &&
          order.total != null &&
          (order.total! - (order.goodsTotal! - order.discount)).abs() < .01;
      final revenues = <ReportProductGroup, num?>{
        for (final key in weights.keys)
          key: netReconciled && weights[key] != null && discounts[key] != null
              ? weights[key]! - discounts[key]!
              : null,
      };
      final collected = _allocate(netReconciled ? order.paid : null, revenues);
      final balancesMatch =
          order.total != null &&
          order.paid != null &&
          order.due != null &&
          (order.total! - order.paid! - order.due!).abs() < .01;
      final remaining = <ReportProductGroup, num?>{
        for (final key in weights.keys)
          key: balancesMatch && revenues[key] != null && collected[key] != null
              ? revenues[key]! - collected[key]!
              : null,
      };
      for (final entry in groups.entries) {
        final group = entry.key;
        final subsetCosts = saleCosts(entry.value),
            subsetPurchase = salePurchaseCost(entry.value);
        final net = revenues[group];
        final subset = groups.length == 1
            ? List<dynamic>.from(salesRows.last)
            : <dynamic>[
                header['IdHoaDon'],
                header['NgayMua'],
                customers['${header['IdKH']}']?['TenKhachHang'],
                entry.value.map(lineName).where((n) => n.isNotEmpty).join('\n'),
                weights[group],
                discounts[group],
                net,
                collected[group],
                remaining[group],
                subsetCosts,
                subsetPurchase,
                net == null || subsetCosts == null || subsetPurchase == null
                    ? null
                    : net - subsetCosts - subsetPurchase,
              ];
        groupedSales.putIfAbsent(group, () => []).add(subset);
      }
    }
    final receiptRows = <List<dynamic>>[],
        receiptSums = List.generate(5, (_) => _Sum());
    var receiptMismatch = 0;
    final receiptMismatchIds = <dynamic>[];
    for (final row in table('NhapHang').where(
      (r) => r['TrangThaiLuu'] != 'dang_luu' && range.contains(r['NgayNhap']),
    )) {
      final total = _number(row['SoTien']),
          paid = _number(row['SoTienDaTra']),
          due = _number(row['SoTienConNo']);
      if (total != null &&
          paid != null &&
          due != null &&
          (total - paid - due).abs() > 0.01) {
        receiptMismatch++;
        receiptMismatchIds.add(row['IdNhapHang']);
      }
      final values = <dynamic>[1, row['SoLuong'], total, paid, due];
      receiptRows.add([
        row['IdNhapHang'],
        row['NgayNhap'],
        directoryName(
          partners['${row['IdDoiTac']}'],
          'TenDoiTac',
          row['NoiNhap'],
        ),
        directoryName(
          carriers['${row['IdVanChuyen']}'],
          'TenVanChuyen',
          row['NguoiCho'],
        ),
        ...values.skip(1),
      ]);
      for (var i = 0; i < values.length; i++) {
        receiptSums[i].add(values[i]);
      }
      final group = switch (row['LoaiSanPham']) {
        'xe_cu' => ReportProductGroup.usedVehicles,
        'phu_tung' => ReportProductGroup.parts,
        'dich_vu' => ReportProductGroup.services,
        'xe_moi' || null => ReportProductGroup.newVehicles,
        _ => ReportProductGroup.unknown,
      };
      groupedReceipts
          .putIfAbsent(group, () => [])
          .add(List<dynamic>.from(receiptRows.last));
    }
    final stockRows = <List<dynamic>>[];
    final stockNotes = <String>[];
    for (final condition in ['moi', 'cu']) {
      final available = table('Xe')
          .where(
            (v) =>
                v['DaXoa'] != true &&
                v['TinhTrang'] == true &&
                v['DangNhapHang'] == null &&
                v['GiuChoBanHang'] == null &&
                v['TinhTrangXe'] == condition,
          )
          .toList();
      final cost = _sumValues(available.map((v) => v['GiaNhap']));
      stockRows.add([
        condition == 'moi' ? 'Xe mới' : 'Xe cũ',
        available.length,
        cost,
      ]);
      final missing = available
          .where((v) => _number(v['GiaNhap']) == null)
          .length;
      if (missing > 0) {
        stockNotes.add(
          '$missing ${condition == 'moi' ? 'xe mới' : 'xe cũ'} chưa có giá nhập.',
        );
      }
    }
    final parts = table('SanPham')
        .where((r) => r['LoaiSanPham'] == 'phu_tung' && r['DaXoa'] != true)
        .toList();
    final stocks = {
      for (final row in table('TonKhoPhuTung')) row['IdSanPham']: row,
    };
    final quantities = <dynamic>[], costs = <dynamic>[];
    var uncounted = 0;
    for (final part in parts) {
      final row = stocks[part['IdSanPham']];
      final qty = _number(row?['SoLuongTon']);
      if (qty == null) {
        uncounted++;
        quantities.add(null);
        costs.add(null);
        continue;
      }
      quantities.add(qty);
      final price = _number(row?['GiaVonThamKhao']);
      costs.add(
        qty == 0
            ? 0
            : price == null
            ? null
            : qty * price,
      );
    }
    stockRows.add(['Phụ tùng', _sumValues(quantities), _sumValues(costs)]);
    if (uncounted > 0) {
      stockNotes.add('$uncounted phụ tùng chưa ghi nhận tồn kho.');
    }
    stockNotes.add(
      'Giá trị tồn kho dựa trên giá nhập xe và giá vốn tham khảo của phụ tùng, chưa cộng chi phí.',
    );
    final debtRows = <List<dynamic>>[];
    final debtNotes = <String>[];
    void debtGroup(
      String label,
      Iterable<Map<String, dynamic>> rows,
      String amount,
      String dueDate,
    ) {
      var count = 0,
          overdue = 0,
          unknown = 0,
          missingDate = 0,
          negativeCount = 0;
      final negativeIds = <dynamic>[];
      num total = 0;
      for (final row in rows) {
        final due = _number(row[amount]);
        if (due == null) {
          unknown++;
          continue;
        }
        if (due < 0) {
          negativeCount++;
          if (row['IdHoaDon'] != null) negativeIds.add(row['IdHoaDon']);
          continue;
        }
        if (due == 0) continue;
        count++;
        total += due;
        final date = row[dueDate];
        if (date is! DateTime) missingDate++;
        if (date is DateTime && financeDay(date).isBefore(today)) overdue++;
      }
      debtRows.add([label, count, total, overdue]);
      if (missingDate > 0) {
        debtNotes.add('$label: $missingDate khoản chưa ghi ngày hẹn.');
      }
      if (unknown > 0) {
        debtNotes.add(
          '$label: $unknown khoản chưa có số dư; tổng còn nợ chỉ gồm các khoản nợ dương đã ghi nhận.',
        );
      }
      if (negativeCount > 0) {
        debtNotes.add(
          '$label: $negativeCount khoản có số dư âm${negativeIds.isEmpty ? '' : ', mã đơn ${negativeIds.take(10).join(', ')}'}; cần đối chiếu số liệu gốc.',
        );
      }
    }

    final orderById = {for (final r in orders) r['IdHoaDon']: r};
    debtGroup(
      'Khách nợ bán hàng',
      [
        for (final d in table('SoNo'))
          if (orderById[d['IdHoaDon']] != null)
            {...d, 'NgayHen': orderById[d['IdHoaDon']]!['NgayHen']},
      ],
      'SoTienConNo',
      'NgayHen',
    );
    debtGroup('Nợ cũ', table('NoCu'), 'SoCoNo', 'NgayHen');
    debtGroup(
      'Nợ nhà cung cấp',
      table('NhapHang').where((r) => r['TrangThaiLuu'] != 'dang_luu'),
      'SoTienConNo',
      'NgayHen',
    );
    debtGroup('Vay vốn', table('VayVon'), 'TongConNo', 'NgayHen');
    String address(Map<String, dynamic>? customer) =>
        '${customer?['DiaChiChiTiet'] ?? ''}'.trim();
    int? overdueDays(dynamic date) => date is DateTime
        ? today.difference(financeDay(date)).inDays.clamp(0, 1000000)
        : null;
    final customerDebtRows = <List<dynamic>>[];
    for (final debt in table('SoNo')) {
      final due = _number(debt['SoTienConNo']),
          header = orderById[debt['IdHoaDon']];
      if (header == null || due == null || due <= 0) continue;
      final customer = customers['${header['IdKH']}'];
      customerDebtRows.add([
        header['IdHoaDon'],
        header['NgayMua'],
        customer?['TenKhachHang'],
        customer?['SoDienThoai'],
        address(customer),
        detailsFor(header).total,
        debt['SoTienDaTra'],
        due,
        header['NgayHen'],
        overdueDays(header['NgayHen']),
      ]);
    }
    final supplierDebtRows = <List<dynamic>>[];
    for (final batch in table('NhapHang')) {
      final due = _number(batch['SoTienConNo']);
      if (batch['TrangThaiLuu'] == 'dang_luu' || due == null || due <= 0) {
        continue;
      }
      final partner = partners['${batch['IdDoiTac']}'];
      supplierDebtRows.add([
        batch['IdNhapHang'],
        batch['NgayNhap'],
        directoryName(partner, 'TenDoiTac', batch['NoiNhap']),
        partner?['SoDienThoai'],
        partner?['DiaChi'],
        batch['SoTien'],
        batch['SoTienDaTra'],
        due,
        batch['NgayHen'],
        overdueDays(batch['NgayHen']),
      ]);
    }
    final pawnPrincipal = <dynamic, List<dynamic>>{};
    for (final p in table('TraNoCamDo')) {
      pawnPrincipal.putIfAbsent(p['IdCamDo'], () => []).add(p['TienGoc']);
    }
    final activePawns = <Map<String, dynamic>>[];
    for (final p in table('CamDo').where((r) => r['TrangThai'] == false)) {
      final original = _number(p['SoTienVay']),
          paid = _sumValues(pawnPrincipal[p['IdCamDo']] ?? []);
      activePawns.add({
        ...p,
        'ConNoBaoCao': original == null || paid == null
            ? null
            : original - paid,
      });
    }
    final pawnDebtRows = <List<dynamic>>[
      for (final p in activePawns)
        [
          p['IdCamDo'],
          p['NgayVay'],
          customers['${p['IdKhachHang']}']?['TenKhachHang'],
          p['TaiSanTheChap'],
          p['NgayHan'],
          p['SoTienVay'],
          _sumValues(pawnPrincipal[p['IdCamDo']] ?? []),
          p['ConNoBaoCao'],
        ],
    ];
    final cashRows = <List<dynamic>>[];
    final income = _Sum(), expense = _Sum();
    var unknownType = 0;
    for (final row in table(
      'ThuChiKhac',
    ).where((r) => range.contains(r['NgayThang']))) {
      final n = _number(row['SoTien']);
      cashRows.add([
        row['ThuChiId'],
        row['NgayThang'],
        row['ThuChi'] == true
            ? 'Thu'
            : row['ThuChi'] == false
            ? 'Chi'
            : null,
        row['LyDo'],
        n,
        CashCategory.nameFor(row),
      ]);
      if (row['ThuChi'] == true) {
        income.add(n);
      } else if (row['ThuChi'] == false) {
        expense.add(n);
      } else {
        unknownType++;
      }
    }
    final pawnRows = <List<dynamic>>[], collectionRows = <List<dynamic>>[];
    final issuedPrincipal = _Sum(),
        collectedPrincipal = _Sum(),
        collectedInterest = _Sum();
    final pawnById = {for (final row in table('CamDo')) row['IdCamDo']: row};
    for (final row in table(
      'CamDo',
    ).where((r) => range.contains(r['NgayVay']))) {
      pawnRows.add([
        row['IdCamDo'],
        row['NgayVay'],
        customers['${row['IdKhachHang']}']?['TenKhachHang'],
        row['TaiSanTheChap'],
        row['SoTienVay'],
      ]);
      issuedPrincipal.add(row['SoTienVay']);
    }
    for (final row in table(
      'TraNoCamDo',
    ).where((r) => range.contains(r['NgayTra']))) {
      final contract = pawnById[row['IdCamDo']];
      collectionRows.add([
        row['IdTraNoCamDo'],
        row['NgayTra'],
        row['IdCamDo'],
        customers['${contract?['IdKhachHang']}']?['TenKhachHang'],
        row['TienGoc'],
        row['SoTienLai'],
      ]);
      collectedPrincipal.add(row['TienGoc']);
      collectedInterest.add(row['SoTienLai']);
    }
    final debtById = {for (final d in table('SoNo')) d['IdSoNo']: d};
    final batchesById = {
      for (final b in table('NhapHang'))
        if (b['TrangThaiLuu'] != 'dang_luu') b['IdNhapHang']: b,
    };
    final oldById = {for (final d in table('NoCu')) d['Id']: d};
    final fundingById = {for (final d in table('VayVon')) d['IdVayVon']: d};
    final customerPaymentRows = <List<dynamic>>[],
        supplierPaymentRows = <List<dynamic>>[],
        oldPaymentRows = <List<dynamic>>[],
        fundingPaymentRows = <List<dynamic>>[];
    for (final p in table('TraNo').where((r) => range.contains(r['NgayTra']))) {
      final debt = debtById[p['IdSoNo']], header = orderById[debt?['IdHoaDon']];
      if (header == null) continue;
      customerPaymentRows.add([
        p['IdTraNo'],
        p['NgayTra'],
        header['IdHoaDon'],
        customers['${header['IdKH']}']?['TenKhachHang'],
        p['SotienTra'],
        p['LaiThu'],
        p['SoCoNo'],
        p['GhiChu'],
      ]);
    }
    for (final p in table(
      'TraNoNhapHang',
    ).where((r) => range.contains(r['NgayTra']))) {
      final batch = batchesById[p['IdNhapHang']];
      if (batch == null) continue;
      supplierPaymentRows.add([
        p['IdTraNoNhapHang'],
        p['NgayTra'],
        p['IdNhapHang'],
        directoryName(
          partners['${batch['IdDoiTac']}'],
          'TenDoiTac',
          batch['NoiNhap'],
        ),
        p['SoTienTra'],
        p['SoCoNo'],
        p['GhiChu'],
      ]);
    }
    for (final p in table(
      'TraNoCu',
    ).where((r) => range.contains(r['NgayTra']))) {
      final debt = oldById[p['IdNoCu']];
      if (debt == null) continue;
      oldPaymentRows.add([
        p['Id'],
        p['NgayTra'],
        p['IdNoCu'],
        customers['${debt['IdKH']}']?['TenKhachHang'],
        p['SoTienTra'],
        p['LaiThu'],
        p['ConNo'],
      ]);
    }
    for (final p in table(
      'TraNoVayVon',
    ).where((r) => range.contains(r['NgayTra']))) {
      final loan = fundingById[p['IdVayVon']];
      if (loan == null) continue;
      fundingPaymentRows.add([
        p['IdTraNoVayVon'],
        p['NgayTra'],
        p['IdVayVon'],
        loan['DoiTac'],
        p['SoTienTraGoc'],
        p['SoTienTraLai'],
        p['ConNoGoc'],
      ]);
    }
    ReportSection payments(
      List<List<dynamic>> rows, {
      required String parent,
      required String name,
      required String principal,
      String? interest,
      bool notes = false,
    }) => ReportSection(
      columns: [
        const ReportColumn('Mã phiếu', width: 90),
        const ReportColumn('Ngày trả', width: 120),
        ReportColumn(parent, width: 100),
        ReportColumn(name, width: 220),
        ReportColumn(principal, money: true),
        if (interest != null) ReportColumn(interest, money: true),
        const ReportColumn('Còn nợ sau trả', money: true),
        if (notes) const ReportColumn('Ghi chú', width: 220),
      ],
      rows: _sortVouchers(rows),
      totals: {
        principal: _sumValues(rows.map((r) => r[4])),
        ?interest: _sumValues(rows.map((r) => r[5])),
      },
    );
    final result = ReportsData({
      ReportKind.sales: ReportSection(
        columns: const [
          ReportColumn('Mã', width: 80),
          ReportColumn('Ngày', width: 110),
          ReportColumn('Khách hàng', width: 180),
          ReportColumn('Sản phẩm / dịch vụ', width: 300),
          ReportColumn('Tiền hàng', money: true),
          ReportColumn('Giảm giá', money: true),
          ReportColumn('Doanh thu', money: true),
          ReportColumn('Đã thu', money: true),
          ReportColumn('Còn nợ', money: true),
          ReportColumn('Chi phí', money: true),
          ReportColumn('Giá nhập', money: true),
          ReportColumn('Lợi nhuận', money: true),
        ],
        rows: _sortVouchers(salesRows),
        totals: {
          'Số đơn': salesSums[0].total,
          'Tiền hàng': salesSums[1].total,
          'Giảm giá': salesSums[2].total,
          'Doanh thu': salesSums[3].total,
          'Đã thu': salesSums[4].total,
          'Còn nợ': salesSums[5].total,
          'Chi phí': salesSums[6].total,
          'Giá nhập': salesSums[7].total,
          'Lợi nhuận': salesSums[8].total,
          'Lợi nhuận đã xác định':
              salesRows.every((row) => row.last == null) && salesRows.isNotEmpty
              ? null
              : salesSums[8].value,
          'Đơn thiếu lợi nhuận': salesSums[8].missing,
        },
        notes: [
          if (salesMismatchIds.isNotEmpty)
            '${salesMismatchIds.length} đơn có tổng thanh toán khác tổng đã thu và còn nợ. Mã: ${salesMismatchIds.take(10).join(', ')}.',
          if (missingSales > 0)
            '$missingSales đơn chưa đủ số liệu. Ô trống và tổng để trống khi thiếu dữ liệu.',
          if (salesSums[8].missing > 0)
            '${salesSums[8].missing} đơn chưa xác định lợi nhuận do thiếu doanh thu, giá nhập hoặc chi phí. Lợi nhuận đã xác định chỉ cộng các đơn đủ dữ liệu; không coi giá vốn thiếu là 0.',
        ],
      ),
      ReportKind.receipts: ReportSection(
        columns: const [
          ReportColumn('Mã lô', width: 80),
          ReportColumn('Ngày', width: 110),
          ReportColumn('Đối tác', width: 180),
          ReportColumn('Vận chuyển', width: 180),
          ReportColumn('Số lượng', width: 90),
          ReportColumn('Tiền nhập', money: true),
          ReportColumn('Đã trả của lô', money: true),
          ReportColumn('Còn nợ của lô', money: true),
        ],
        rows: _sortVouchers(receiptRows),
        totals: {
          'Số lô': receiptSums[0].total,
          'Số lượng': receiptSums[1].total,
          'Tiền nhập': receiptSums[2].total,
          'Đã trả của lô': receiptSums[3].total,
          'Còn nợ của lô': receiptSums[4].total,
        },
        notes: [
          'Đã trả và còn nợ là số hiện tại của các lô trong kỳ.',
          if (receiptMismatch > 0)
            '$receiptMismatch lô có tiền nhập khác tổng đã trả và còn nợ. Mã: ${receiptMismatchIds.take(10).join(', ')}. Giữ số liệu gốc để đối chiếu.',
        ],
      ),
      ReportKind.stock: ReportSection(
        columns: const [
          ReportColumn('Nhóm sản phẩm', width: 220),
          ReportColumn('Số lượng tồn', width: 160),
          ReportColumn('Giá trị tham khảo', money: true, width: 220),
        ],
        rows: stockRows,
        totals: {
          'Xe mới': stockRows[0][1] as num?,
          'Xe cũ': stockRows[1][1] as num?,
          'Phụ tùng': stockRows[2][1] as num?,
        },
        notes: stockNotes,
      ),
      ReportKind.debts: ReportSection(
        columns: const [
          ReportColumn('Khoản nợ', width: 230),
          ReportColumn('Số khoản', width: 100),
          ReportColumn('Còn nợ', money: true, width: 180),
          ReportColumn('Quá hạn', width: 100),
        ],
        rows: debtRows,
        totals: {for (final row in debtRows) row[0] as String: row[2] as num?},
        notes: [
          'Số dư hiện tại, không gồm lãi dự tính. Các khoản khách nợ, nợ nhà cung cấp và vay vốn được theo dõi riêng.',
          ...debtNotes,
        ],
      ),
      ReportKind.customerDebt: ReportSection(
        columns: const [
          ReportColumn('Mã đơn', width: 90),
          ReportColumn('Ngày bán', width: 110),
          ReportColumn('Khách hàng', width: 190),
          ReportColumn('Số điện thoại'),
          ReportColumn('Địa chỉ', width: 220),
          ReportColumn('Tổng thanh toán', money: true),
          ReportColumn('Đã thu', money: true),
          ReportColumn('Còn nợ', money: true),
          ReportColumn('Ngày hẹn', width: 110),
          ReportColumn('Quá hạn (ngày)', width: 90),
        ],
        rows: _sortVouchers(customerDebtRows),
        totals: {
          'Tổng thanh toán': _sumValues(customerDebtRows.map((r) => r[5])),
          'Đã thu': _sumValues(customerDebtRows.map((r) => r[6])),
          'Còn nợ': _sumValues(customerDebtRows.map((r) => r[7])),
        },
        notes: const [
          'Các đơn bán còn nợ tại thời điểm cập nhật, không gồm lãi dự tính.',
        ],
      ),
      ReportKind.supplierDebt: ReportSection(
        columns: const [
          ReportColumn('Mã lô', width: 90),
          ReportColumn('Ngày nhập', width: 110),
          ReportColumn('Đối tác', width: 190),
          ReportColumn('Số điện thoại'),
          ReportColumn('Địa chỉ', width: 220),
          ReportColumn('Tiền nhập', money: true),
          ReportColumn('Đã trả', money: true),
          ReportColumn('Còn nợ', money: true),
          ReportColumn('Ngày hẹn', width: 110),
          ReportColumn('Quá hạn (ngày)', width: 90),
        ],
        rows: _sortVouchers(supplierDebtRows),
        totals: {
          'Tiền nhập': _sumValues(supplierDebtRows.map((r) => r[5])),
          'Đã trả': _sumValues(supplierDebtRows.map((r) => r[6])),
          'Còn nợ': _sumValues(supplierDebtRows.map((r) => r[7])),
        },
        notes: const [
          'Các lô hàng còn nợ nhà cung cấp tại thời điểm cập nhật.',
        ],
      ),
      ReportKind.customerRepayments: payments(
        customerPaymentRows,
        parent: 'Mã đơn',
        name: 'Khách hàng',
        principal: 'Tiền trả nợ',
        interest: 'Lãi thực thu',
        notes: true,
      ),
      ReportKind.supplierRepayments: payments(
        supplierPaymentRows,
        parent: 'Mã lô',
        name: 'Nhà cung cấp',
        principal: 'Số tiền trả',
        notes: true,
      ),
      ReportKind.oldDebtRepayments: payments(
        oldPaymentRows,
        parent: 'Mã nợ cũ',
        name: 'Khách hàng',
        principal: 'Tiền trả nợ',
        interest: 'Lãi thực thu',
      ),
      ReportKind.fundingRepayments: payments(
        fundingPaymentRows,
        parent: 'Mã vay vốn',
        name: 'Đối tác cho vay',
        principal: 'Trả gốc',
        interest: 'Trả lãi',
      ),
      ReportKind.cash: ReportSection(
        columns: const [
          ReportColumn('Mã', width: 80),
          ReportColumn('Ngày', width: 120),
          ReportColumn('Loại', width: 80),
          ReportColumn('Lý do', width: 300),
          ReportColumn('Số tiền', money: true),
          ReportColumn('Danh mục', width: 210),
        ],
        rows: _sortVouchers(cashRows),
        totals: {'Thu': income.total, 'Chi': expense.total},
        notes: [
          'Chỉ gồm các phiếu tại mục Thu chi, không phải báo cáo số dư tiền mặt toàn cửa hàng.',
          if (unknownType > 0) '$unknownType phiếu chưa xác định Thu hay Chi.',
        ],
      ),
      ReportKind.pawnDebt: ReportSection(
        columns: const [
          ReportColumn('Mã', width: 70),
          ReportColumn('Ngày vay', width: 110),
          ReportColumn('Khách hàng', width: 180),
          ReportColumn('Tài sản', width: 220),
          ReportColumn('Ngày hạn', width: 110),
          ReportColumn('Tiền vay', money: true),
          ReportColumn('Gốc đã thu', money: true),
          ReportColumn('Còn nợ', money: true),
        ],
        rows: _sortVouchers(pawnDebtRows),
        totals: {
          'Phiếu đang cầm': activePawns.length,
          'Tiền vay': _sumValues(pawnDebtRows.map((r) => r[5])),
          'Gốc đã thu': _sumValues(pawnDebtRows.map((r) => r[6])),
          'Còn nợ': _sumValues(pawnDebtRows.map((r) => r[7])),
        },
        notes: const [
          'Dư nợ hiện tại của các phiếu đang cầm, không gồm lãi dự tính.',
        ],
      ),
      ReportKind.pawn: ReportSection(
        columns: const [
          ReportColumn('Mã phiếu', width: 90),
          ReportColumn('Ngày', width: 120),
          ReportColumn('Khách hàng', width: 200),
          ReportColumn('Tài sản', width: 260),
          ReportColumn('Tiền cho vay', money: true),
        ],
        rows: _sortVouchers(pawnRows),
        totals: {
          'Phiếu mới': pawnRows.length,
          'Tiền cho vay': issuedPrincipal.total,
        },
      ),
      ReportKind.pawnCollections: ReportSection(
        columns: const [
          ReportColumn('Mã phiếu', width: 90),
          ReportColumn('Ngày trả', width: 120),
          ReportColumn('Mã cầm đồ', width: 90),
          ReportColumn('Khách hàng', width: 200),
          ReportColumn('Gốc đã thu', money: true),
          ReportColumn('Lãi thực thu', money: true),
        ],
        rows: _sortVouchers(collectionRows),
        totals: {
          'Gốc đã thu': collectedPrincipal.total,
          'Lãi thực thu': collectedInterest.total,
        },
        notes: const [
          'Lãi thực thu lấy theo khoản đã ghi nhận thực thu; bỏ trống khi dữ liệu cũ chưa ghi nhận.',
        ],
      ),
    }, timestamp);
    ReportSection groupSection(ReportKind kind, List<List<dynamic>> rows) {
      final template = result.sections[kind]!;
      final isSales = kind == ReportKind.sales;
      return ReportSection(
        columns: template.columns,
        rows: _sortVouchers(rows),
        totals: {
          isSales ? 'Số đơn' : 'Số lô': rows.length,
          if (isSales) ...{
            'Lợi nhuận đã xác định':
                rows.isNotEmpty && rows.every((r) => r.last == null)
                ? null
                : _sumValues(rows.map((r) => r.last).whereType<num>()),
            'Đơn thiếu lợi nhuận': rows.where((r) => r.last == null).length,
          },
          for (var i = 4; i < template.columns.length; i++)
            template.columns[i].label: _sumValues(rows.map((r) => r[i])),
        },
        notes: [
          if (isSales)
            'Đơn nhiều nhóm: giảm giá, doanh thu, đã thu và còn nợ phân bổ theo giá trị sản phẩm; để trống nếu chưa đủ dữ liệu đối chiếu.',
          ...template.notes,
        ],
      );
    }

    final salesByGroup = {
      for (final group in ReportProductGroup.values.where(
        (g) => g != ReportProductGroup.all,
      ))
        group: groupSection(ReportKind.sales, groupedSales[group] ?? []),
    };
    final receiptsByGroup = {
      for (final group in ReportProductGroup.values.where(
        (g) => g != ReportProductGroup.all,
      ))
        group: groupSection(ReportKind.receipts, groupedReceipts[group] ?? []),
    };
    final customerAging = debtAging(
      [
        for (final debt in table('SoNo'))
          if (orderById[debt['IdHoaDon']] != null)
            {
              'Amount': debt['SoTienConNo'],
              'Due': orderById[debt['IdHoaDon']]!['NgayHen'],
            },
        for (final debt in table('NoCu'))
          {'Amount': debt['SoCoNo'], 'Due': debt['NgayHen']},
      ],
      amountKey: 'Amount',
      dateKey: 'Due',
      today: today,
    );
    final pawnAging = debtAging(
      activePawns,
      amountKey: 'ConNoBaoCao',
      dateKey: 'NgayHan',
      today: today,
      includeUnknownAmounts: true,
    );
    final complete = ReportsData(
      result.sections,
      timestamp,
      salesByGroup: salesByGroup,
      receiptsByGroup: receiptsByGroup,
      customerAging: customerAging,
      pawnAging: pawnAging,
      cashflow: _cashflow(range, source),
    );
    final pending = source.values
        .expand((rows) => rows)
        .any(
          (row) =>
              row['ThanhToanDangLuu'] is Map ||
              row['TrangThaiLuu'] == 'dang_luu',
        );
    if (!pending) return complete;
    ReportSection pendingSection(ReportSection section) => ReportSection(
      columns: section.columns,
      rows: section.rows,
      totals: section.totals,
      notes: [
        'Có giao dịch đang lưu. Hoàn tất giao dịch rồi cập nhật báo cáo để đối chiếu số liệu.',
        ...section.notes,
      ],
    );
    return ReportsData(
      {
        for (final entry in result.sections.entries)
          entry.key: ReportSection(
            columns: entry.value.columns,
            rows: entry.value.rows,
            totals: entry.value.totals,
            notes: [
              'Có giao dịch đang lưu. Hoàn tất giao dịch rồi cập nhật báo cáo để đối chiếu số liệu.',
              ...entry.value.notes,
            ],
          ),
      },
      timestamp,
      salesByGroup: {
        for (final entry in salesByGroup.entries)
          entry.key: pendingSection(entry.value),
      },
      receiptsByGroup: {
        for (final entry in receiptsByGroup.entries)
          entry.key: pendingSection(entry.value),
      },
      customerAging: customerAging,
      pawnAging: pawnAging,
      cashflow: complete.cashflow,
    );
  }

  static ReportCashflow _cashflow(
    ReportRange range,
    Map<String, List<Map<String, dynamic>>> source,
  ) {
    List<Map<String, dynamic>> table(String name) => source[name] ?? [];
    List<Map<String, dynamic>> inPeriod(String name, String dateKey) =>
        table(name).where((row) => range.contains(row[dateKey])).toList();
    num? sum(Iterable<dynamic> values) => _sumValues(values);

    final income = <String, num?>{
      'Bán hàng': sum(
        inPeriod(
          'HoaDonBan',
          'NgayMua',
        ).map((row) => row['SoTienDaTra'] ?? row['SoTienKhachDua'] ?? 0),
      ),
      'Cầm đồ - gốc': sum(
        inPeriod('TraNoCamDo', 'NgayTra').map((row) => row['TienGoc']),
      ),
      'Cầm đồ - lãi': sum(
        inPeriod('TraNoCamDo', 'NgayTra').map((row) => row['SoTienLai']),
      ),
      'Thu nợ - gốc': sum([
        ...inPeriod('TraNoCu', 'NgayTra').map((row) => row['SoTienTra']),
      ]),
      'Thu nợ - lãi': sum([
        ...inPeriod('TraNoCu', 'NgayTra').map((row) => row['LaiThu']),
      ]),
      'Thu khác': sum(
        inPeriod('ThuChiKhac', 'NgayThang')
            .where(
              (row) =>
                  row['ThuChi'] == true &&
                  row['IdDanhMuc'] != 'customer-interest',
            )
            .map((row) => row['SoTien']),
      ),
      'Vay vốn': sum(
        inPeriod('VayVon', 'NgayVay').map((row) => row['SoTienVay']),
      ),
    };

    final batchById = {
      for (final row in table('NhapHang')) row['IdNhapHang']: row,
    };
    final purchaseSums = {
      'Nhập xe mới': _Sum(),
      'Nhập xe cũ': _Sum(),
      'Nhập phụ tùng': _Sum(),
      'Nhập dịch vụ': _Sum(),
      'Nhập khác': _Sum(),
    };
    for (final payment in inPeriod('TraNoNhapHang', 'NgayTra')) {
      final batch = batchById[payment['IdNhapHang']];
      final category = switch (batch?['LoaiSanPham']) {
        'xe_moi' => 'Nhập xe mới',
        'xe_cu' => 'Nhập xe cũ',
        'phu_tung' => 'Nhập phụ tùng',
        'dich_vu' => 'Nhập dịch vụ',
        _ => 'Nhập khác',
      };
      purchaseSums[category]!.add(payment['SoTienTra']);
    }
    final fundingPayments = inPeriod('TraNoVayVon', 'NgayTra');
    final expense = <String, num?>{
      for (final entry in purchaseSums.entries) entry.key: entry.value.total,
      'Cầm đồ': sum(
        inPeriod('CamDo', 'NgayVay').map((row) => row['SoTienVay']),
      ),
      'Chi khác': sum(
        inPeriod(
          'ThuChiKhac',
          'NgayThang',
        ).where((row) => row['ThuChi'] == false).map((row) => row['SoTien']),
      ),
      'Trả lãi vay vốn': sum(fundingPayments.map((row) => row['SoTienTraLai'])),
      'Trả gốc vay vốn': sum(fundingPayments.map((row) => row['SoTienTraGoc'])),
    };
    return ReportCashflow(income: income, expense: expense);
  }
}
