import 'package:intl/intl.dart';
import '../pawn/pawn_models.dart';
import '../customers/customer_models.dart';

/// A print snapshot. Supplemental identity fields never modify the saved pawn.
class PawnContractData {
  PawnContractData(PawnDetails details)
    : id = (details.contract['IdCamDo'] as num).toInt(),
      amount = _amount(details.contract['SoTienVay']),
      loanDate = details.contract['NgayVay'] as DateTime?,
      dueDate = details.contract['NgayHan'] as DateTime?,
      asset = '${details.contract['TaiSanTheChap'] ?? ''}',
      borrowerName = '${details.customer?['TenKhachHang'] ?? ''}',
      phone = '${details.customer?['SoDienThoai'] ?? ''}',
      address =
          (details.customer?['DiaChiHienThi']?.toString().trim().isNotEmpty ??
              false)
          ? details.customer!['DiaChiHienThi'].toString().trim()
          : '${details.customer?['DiaChiChiTiet'] ?? ''}'.trim() {
    final customer = details.customer;
    final cccd = '${customer?['SoCCCD'] ?? ''}'.trim();
    identityNumber = cccd.isNotEmpty ? cccd : '${customer?['SoCMND'] ?? ''}';
    identityDate = CustomerDraft.formatIssueDate(customer?['NgayCap']);
    identityPlace = '${customer?['NoiCap'] ?? ''}';
  }

  final int id, amount;
  final DateTime? loanDate, dueDate;
  final String asset;
  String borrowerName, phone, address;
  String identityNumber = '',
      identityDate = '',
      identityPlace = '',
      authorizedPerson = '';

  static int _amount(dynamic value) {
    if (value is! num ||
        !value.isFinite ||
        value <= 0 ||
        value > 1000000000000000 ||
        value != value.round()) {
      throw const FormatException(
        'Số tiền trên phiếu không hợp lệ để in hợp đồng.',
      );
    }
    return value.toInt();
  }

  Map<String, String> get values {
    String filled(String text) =>
        text.trim().isEmpty ? '……………………' : text.trim();
    String part(DateTime? date, int Function(DateTime) get) =>
        date == null ? '……' : '${get(date)}';
    final start = loanDate;
    final end = dueDate;
    final days = start == null || end == null
        ? null
        : DateTime.utc(
            end.year,
            end.month,
            end.day,
          ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    return {
      'borrowerName': filled(borrowerName),
      'phone': filled(phone),
      'address': filled(address),
      'identityNumber': filled(identityNumber),
      'identityDate': filled(identityDate),
      'identityPlace': filled(identityPlace),
      'authorizedPerson': filled(authorizedPerson),
      'asset': filled(asset),
      'amount': NumberFormat('#,##0', 'vi_VN').format(amount),
      'amountWords': vietnameseMoneyWords(amount),
      'loanDay': part(start, (d) => d.day),
      'loanMonth': part(start, (d) => d.month),
      'loanYear': part(start, (d) => d.year),
      'dueDay': part(end, (d) => d.day),
      'dueMonth': part(end, (d) => d.month),
      'dueYear': part(end, (d) => d.year),
      'termDays': days == null || days < 0 ? '……' : '$days',
    };
  }
}

String vietnameseMoneyWords(int amount) {
  if (amount < 0 || amount > 1000000000000000) {
    throw ArgumentError.value(amount);
  }
  if (amount == 0) return 'Không đồng';
  const digits = [
    'không',
    'một',
    'hai',
    'ba',
    'bốn',
    'năm',
    'sáu',
    'bảy',
    'tám',
    'chín',
  ];
  const units = ['', 'nghìn', 'triệu', 'tỷ', 'nghìn tỷ', 'triệu tỷ'];
  String group(int value, bool full) {
    final h = value ~/ 100, t = value ~/ 10 % 10, u = value % 10;
    final words = <String>[];
    if (h > 0 || full) words.add('${digits[h]} trăm');
    if (t > 1) {
      words.add('${digits[t]} mươi');
    } else if (t == 1) {
      words.add('mười');
    } else if ((h > 0 || full) && u > 0) {
      words.add('lẻ');
    }
    if (u > 0) {
      words.add(
        u == 1 && t > 1
            ? 'mốt'
            : u == 5 && t > 0
            ? 'lăm'
            : digits[u],
      );
    }
    return words.join(' ');
  }

  final groups = <int>[];
  var remaining = amount;
  while (remaining > 0) {
    groups.add(remaining % 1000);
    remaining ~/= 1000;
  }
  final words = <String>[];
  for (var i = groups.length - 1; i >= 0; i--) {
    if (groups[i] == 0) continue;
    words.add(group(groups[i], i != groups.length - 1));
    if (units[i].isNotEmpty) words.add(units[i]);
  }
  final text = '${words.join(' ')} đồng chẵn';
  return '${text[0].toUpperCase()}${text.substring(1)}';
}
