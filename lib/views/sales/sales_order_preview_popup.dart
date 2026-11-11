import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../models/printing/sales_invoice_data.dart';
import '../../services/sales_invoice_pdf.dart';
import '../widgets/form_popup.dart';

class SalesOrderPreviewPopup extends StatefulWidget {
  const SalesOrderPreviewPopup({super.key, required this.data, this.buildPdf});
  final Future<Uint8List> Function(SalesInvoiceData)? buildPdf;
  final SalesInvoiceData data;
  @override
  State<SalesOrderPreviewPopup> createState() => _SalesOrderPreviewPopupState();
}

class _SalesOrderPreviewPopupState extends State<SalesOrderPreviewPopup> {
  late Future<Uint8List> _document;
  bool _printing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _document = _build();
  }

  Future<Uint8List> _build() =>
      (widget.buildPdf ?? SalesInvoicePdf.build)(widget.data);
  void _retry() => setState(() {
    _error = null;
    _document = _build();
  });
  Future<void> _print(Uint8List bytes) async {
    if (_printing) return;
    setState(() {
      _printing = true;
      _error = null;
    });
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: widget.data.fileName,
        format: PdfPageFormat.a4,
        dynamicLayout: false,
      );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Không in được hóa đơn. Kiểm tra máy in và thử lại; đơn đang nhập vẫn được giữ nguyên.',
        );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_printing,
    child: FormPopup(
      title: 'Xem trước đơn bán hàng',
      canClose: !_printing,
      child: FutureBuilder<Uint8List>(
        future: _document,
        builder: (context, snapshot) => Column(
          children: [
            Expanded(
              child: snapshot.hasError
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Không tạo được bản xem trước.'),
                          TextButton(
                            onPressed: _retry,
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    )
                  : snapshot.hasData
                  ? PdfPreview(
                      key: const ValueKey('sales-invoice-preview'),
                      build: (_) async => snapshot.data!,
                      initialPageFormat: PdfPageFormat.a4,
                      useActions: false,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                      allowSharing: false,
                      allowPrinting: false,
                      onError: (_, _) => const Center(
                        child: Text(
                          'Không hiển thị được hóa đơn. Vui lòng thử mở lại.',
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      Tooltip(
                        message: 'Chờ mẫu hợp đồng mua bán',
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('In hợp đồng mua bán'),
                        ),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('print-sales-invoice'),
                        onPressed: _printing || !snapshot.hasData
                            ? null
                            : () => _print(snapshot.data!),
                        icon: const Icon(Icons.print_outlined),
                        label: Text(
                          _printing ? 'Đang in…' : 'In hóa đơn bán hàng',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
