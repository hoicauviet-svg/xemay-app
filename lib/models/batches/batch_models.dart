import 'dart:typed_data';
import 'package:mongo_dart/mongo_dart.dart' show BsonBinary;

class ReceiptBatch {
  const ReceiptBatch({
    required this.id,
    required this.date,
    required this.quantity,
    required this.total,
    required this.paid,
    required this.remaining,
    required this.deliveredBy,
    required this.origin,
  });
  factory ReceiptBatch.fromMap(Map<String, dynamic> row) => ReceiptBatch(
    id: (row['IdNhapHang'] as num).toInt(),
    date: row['NgayNhap'] as DateTime?,
    quantity: (row['SoLuong'] as num?)?.toInt(),
    total: row['SoTien'] as num?,
    paid: row['SoTienDaTra'] as num?,
    remaining: row['SoTienConNo'] as num?,
    deliveredBy: row['NguoiCho']?.toString() ?? '',
    origin: row['NoiNhap']?.toString() ?? '',
  );
  final int id;
  final DateTime? date;
  final int? quantity;
  final num? total, paid, remaining;
  final String deliveredBy, origin;
}

class BatchPage {
  const BatchPage(this.batches, this.total);
  final List<ReceiptBatch> batches;
  final int total;
}

class BatchProduct {
  const BatchProduct({
    this.sourceId,
    required this.batchId,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.cost,
    this.vehicleId,
    this.frameNumber = '',
    this.engineNumber = '',
    this.plate = '',
  });
  final dynamic sourceId;
  final int batchId, productId;
  final int? vehicleId;
  final String name, frameNumber, engineNumber, plate;
  final num quantity;
  final num? cost;
}

class PaymentDocument {
  PaymentDocument({
    required this.name,
    required this.mimeType,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String name, mimeType;
  final Uint8List bytes;
  static const maxTotalBytes = 8 * 1024 * 1024;
  static String? detectMime(Uint8List b) {
    if (b.length >= 5 && String.fromCharCodes(b.take(5)) == '%PDF-') {
      return 'application/pdf';
    }
    if (b.length >= 8 &&
        b[0] == 137 &&
        String.fromCharCodes(b.skip(1).take(3)) == 'PNG' &&
        b[4] == 13 &&
        b[5] == 10 &&
        b[6] == 26 &&
        b[7] == 10) {
      return 'image/png';
    }
    if (b.length >= 3 && b[0] == 255 && b[1] == 216 && b[2] == 255) {
      return 'image/jpeg';
    }
    if (b.length >= 6 &&
        ['GIF87a', 'GIF89a'].contains(String.fromCharCodes(b.take(6)))) {
      return 'image/gif';
    }
    if (b.length >= 12 &&
        String.fromCharCodes(b.take(4)) == 'RIFF' &&
        String.fromCharCodes(b.skip(8).take(4)) == 'WEBP') {
      return 'image/webp';
    }
    if (b.length >= 12 &&
        String.fromCharCodes(b.skip(4).take(4)) == 'ftyp' &&
        [
          'heic',
          'heix',
          'hevc',
          'hevx',
          'mif1',
        ].contains(String.fromCharCodes(b.skip(8).take(4)))) {
      return 'image/heic';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'TenFile': name,
    'LoaiFile': mimeType,
    'DuLieu': BsonBinary.from(bytes),
  };
  factory PaymentDocument.fromMap(Map<String, dynamic> map) {
    final data = map['DuLieu'];
    return PaymentDocument(
      name: map['TenFile'] as String,
      mimeType: map['LoaiFile'] as String,
      bytes: data is BsonBinary
          ? data.byteList
          : Uint8List.fromList((data as List).cast<int>()),
    );
  }
}

class BatchPaymentException implements Exception {
  const BatchPaymentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BatchPayment {
  const BatchPayment({
    this.documents = const [],
    required this.id,
    required this.batchId,
    required this.date,
    required this.amount,
    required this.remaining,
    required this.notes,
  });
  factory BatchPayment.fromMap(Map<String, dynamic> row) => BatchPayment(
    id: (row['IdTraNoNhapHang'] as num).toInt(),
    batchId: (row['IdNhapHang'] as num).toInt(),
    date: row['NgayTra'] as DateTime?,
    amount: row['SoTienTra'] as num?,
    remaining: row['SoCoNo'] as num?,
    notes: row['GhiChu']?.toString() ?? '',
    documents: [
      for (final d in row['ChungTu'] as List? ?? [])
        PaymentDocument.fromMap(Map<String, dynamic>.from(d as Map)),
    ],
  );
  final List<PaymentDocument> documents;
  final int id, batchId;
  final DateTime? date;
  final num? amount, remaining;
  final String notes;
}

class BatchPaymentPreview {
  const BatchPaymentPreview({
    this.documents = const [],
    required this.batchId,
    required this.amount,
    required this.date,
    required this.notes,
  });
  final List<PaymentDocument> documents;
  final int batchId, amount;
  final DateTime date;
  final String notes;
}

enum BatchDetailTab {
  information('Thông tin'),
  products('Danh sách sản phẩm'),
  paymentHistory('Lịch sử thanh toán'),
  payment('Thanh toán');

  const BatchDetailTab(this.label);
  final String label;
}
