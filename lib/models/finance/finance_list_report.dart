import '../reports/report_models.dart';

typedef FinanceReportExporter =
    Future<bool> Function(String, ReportSection, DateTime);

class FinanceListReport {
  static num? _number(dynamic value) =>
      value is num && value.isFinite ? value : null;
  static num? _sum(Iterable<dynamic> values) {
    num total = 0;
    for (final value in values) {
      final amount = _number(value);
      if (amount == null) return null;
      total += amount;
    }
    return total;
  }

  static ReportSection funding(
    List<Map<String, dynamic>> rows, {
    String search = '',
    String status = 'open',
  }) => ReportSection(
    columns: const [
      ReportColumn('Mã'),
      ReportColumn('Đối tác cho vay'),
      ReportColumn('Số tiền vay', money: true),
      ReportColumn('Đã trả gốc', money: true),
      ReportColumn('Còn nợ gốc', money: true),
      ReportColumn('Lãi suất (%/tháng)'),
      ReportColumn('Ngày vay'),
      ReportColumn('Ngày hẹn'),
      ReportColumn('Ngày tính lãi'),
      ReportColumn('Ghi chú'),
    ],
    rows: [
      for (final r in rows)
        [
          r['IdVayVon'],
          r['DoiTac'],
          r['SoTienVay'],
          _number(r['SoTienVay']) == null || _number(r['TongConNo']) == null
              ? null
              : (r['SoTienVay'] as num) - (r['TongConNo'] as num),
          r['TongConNo'],
          r['LaiSuat'],
          r['NgayVay'],
          r['NgayHen'],
          r['NgayTinhLai'],
          r['GhiChu'],
        ],
    ],
    totals: {
      'Số tiền vay': _sum(rows.map((r) => r['SoTienVay'])),
      'Còn nợ gốc': _sum(rows.map((r) => r['TongConNo'])),
    },
    notes: [
      'Bộ lọc: ${status == 'open'
          ? 'Còn nợ'
          : status == 'closed'
          ? 'Đã tất toán'
          : 'Tất cả'}${search.trim().isEmpty ? '' : '; Tìm kiếm: ${search.trim()}'}',
    ],
  );
  static ReportSection opening(
    List<Map<String, dynamic>> rows, {
    String search = '',
    String status = 'open',
  }) => ReportSection(
    columns: const [
      ReportColumn('Mã'),
      ReportColumn('Khách hàng'),
      ReportColumn('Số điện thoại'),
      ReportColumn('Tổng nợ', money: true),
      ReportColumn('Đã trả', money: true),
      ReportColumn('Còn nợ', money: true),
      ReportColumn('Ngày hẹn'),
      ReportColumn('Ngày tính lãi'),
      ReportColumn('Ghi chú'),
    ],
    rows: [
      for (final r in rows)
        [
          r['Id'],
          (r['KhachHang'] as Map?)?['TenKhachHang'],
          (r['KhachHang'] as Map?)?['SoDienThoai'],
          r['TongNo'],
          r['SoTienDaTra'],
          r['SoCoNo'],
          r['NgayHen'],
          r['NgayTinhLai'],
          r['GhiChu'],
        ],
    ],
    totals: {
      'Tổng nợ': _sum(rows.map((r) => r['TongNo'])),
      'Đã trả': _sum(rows.map((r) => r['SoTienDaTra'])),
      'Còn nợ': _sum(rows.map((r) => r['SoCoNo'])),
    },
    notes: [
      'Bộ lọc: ${status == 'open'
          ? 'Còn nợ'
          : status == 'closed'
          ? 'Đã trả hết'
          : 'Tất cả'}${search.trim().isEmpty ? '' : '; Tìm kiếm: ${search.trim()}'}',
    ],
  );
}
