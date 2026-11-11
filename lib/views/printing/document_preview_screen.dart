import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../widgets/app_top_bar.dart';

class DocumentPreviewScreen extends StatelessWidget {
  const DocumentPreviewScreen({
    super.key,
    required this.bytes,
    required this.title,
    required this.fileName,
  });
  final Uint8List bytes;
  final String title, fileName;
  Future<void> _save(BuildContext context) async {
    try {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PDF', extensions: ['pdf']),
        ],
      );
      if (location == null) return;
      await XFile.fromData(
        bytes,
        name: fileName,
        mimeType: 'application/pdf',
      ).saveTo(location.path);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không lưu được PDF. Vui lòng chọn lại nơi lưu.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(
      title: title,
      actions: [
        IconButton(
          tooltip: 'Lưu PDF',
          onPressed: () => _save(context),
          icon: const Icon(Icons.save_alt),
        ),
      ],
    ),
    body: PdfPreview(
      build: (_) async => bytes,
      pdfFileName: fileName,
      initialPageFormat: PdfPageFormat.a4,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowSharing: false,
      onError: (_, _) => const Center(
        child: Text('Không hiển thị được bản in. Vui lòng thử lại.'),
      ),
      onPrintError: (context, _) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không in được hóa đơn. Kiểm tra máy in và thử lại.'),
        ),
      ),
    ),
  );
}
