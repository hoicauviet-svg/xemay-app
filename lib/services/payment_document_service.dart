import 'package:file_selector/file_selector.dart';
import '../models/batches/batch_models.dart';

class PaymentDocumentService {
  static const _types = XTypeGroup(
    label: 'Ảnh hoặc PDF',
    extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'pdf'],
    uniformTypeIdentifiers: ['public.image', 'com.adobe.pdf'],
  );
  static Future<List<PaymentDocument>> pick() async {
    final files = await openFiles(acceptedTypeGroups: [_types]);
    if (files.length > 10) {
      throw const BatchPaymentException('Chọn tối đa 10 chứng từ.');
    }
    final documents = <PaymentDocument>[];
    int total = 0;
    for (final file in files) {
      total += await file.length();
      if (total > PaymentDocument.maxTotalBytes) {
        throw const BatchPaymentException(
          'Tổng dung lượng chứng từ tối đa 8 MB.',
        );
      }
      final bytes = await file.readAsBytes();
      final mime = PaymentDocument.detectMime(bytes);
      if (mime == null) {
        throw BatchPaymentException(
          'File ${file.name} không phải ảnh hoặc PDF được hỗ trợ.',
        );
      }
      documents.add(
        PaymentDocument(name: file.name, mimeType: mime, bytes: bytes),
      );
    }
    return documents;
  }

  static Future<bool> saveCopy(PaymentDocument document) async {
    final target = await getSaveLocation(suggestedName: document.name);
    if (target == null) return false;
    await XFile.fromData(
      document.bytes,
      name: document.name,
      mimeType: document.mimeType,
    ).saveTo(target.path);
    return true;
  }
}
