import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../models/printing/sale_contract_data.dart';
import '../../models/printing/sales_invoice_data.dart';
import '../../services/sale_contract_pdf.dart';
import '../../services/sales_invoice_pdf.dart';
import '../widgets/form_popup.dart';

class SalesOrderPreviewPopup extends StatefulWidget {
  const SalesOrderPreviewPopup({
    super.key,
    required this.data,
    this.buildPdf,
    this.buildContractPdf,
    this.printDocument,
    this.initialTab = 0,
  });
  final Future<Uint8List> Function(SalesInvoiceData)? buildPdf;
  final Future<Uint8List> Function(SalesInvoiceData)? buildContractPdf;
  final Future<void> Function(Uint8List bytes, String name)? printDocument;
  final SalesInvoiceData data;
  final int initialTab;
  @override
  State<SalesOrderPreviewPopup> createState() => _SalesOrderPreviewPopupState();
}

class _SalesOrderPreviewPopupState extends State<SalesOrderPreviewPopup>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late Future<Uint8List> _invoice;
  Future<Uint8List>? _contract;
  bool _printing = false;
  String? _error;
  int? _errorTab;
  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab == 1 ? 1 : 0;
    _tabs = TabController(length: 2, vsync: this, initialIndex: tab);
    _invoice = _buildInvoice();
    if (tab == 1) _contract = _buildContract();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<Uint8List> _buildInvoice() =>
      (widget.buildPdf ?? SalesInvoicePdf.build)(widget.data);
  Future<Uint8List> _buildContract() =>
      (widget.buildContractPdf ?? SaleContractPdf.build)(widget.data);

  void _openContract() {
    if (_contract == null) {
      setState(() {
        _contract = _buildContract();
      });
    }
  }

  Future<void> _send(
    int tab,
    Future<Uint8List> Function() build,
    String name,
    String failure,
  ) async {
    if (_printing) return;
    setState(() {
      _printing = true;
      _error = null;
      _errorTab = null;
    });
    try {
      final bytes = await build();
      await (widget.printDocument ?? _systemPrint)(bytes, name);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = failure;
          _errorTab = tab;
        });
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _systemPrint(Uint8List bytes, String name) => Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: name,
    format: PdfPageFormat.a4,
    dynamicLayout: false,
  );

  Future<void> _printInvoice() => _send(
    0,
    () => _invoice,
    widget.data.fileName,
    widget.data.saved
        ? 'Không in được hóa đơn. Kiểm tra máy in và thử lại. Đơn #${widget.data.invoiceId} đã được lưu.'
        : 'Không in được hóa đơn. Kiểm tra máy in và thử lại; đơn đang nhập vẫn được giữ nguyên.',
  );

  Future<void> _printContract() {
    _contract ??= _buildContract();
    return _send(
      1,
      () => _contract!,
      SaleContractData(widget.data).fileName,
      widget.data.saved
          ? 'Không in được hợp đồng mua bán. Kiểm tra máy in và thử lại. Đơn #${widget.data.invoiceId} đã được lưu.'
          : 'Không in được hợp đồng mua bán. Kiểm tra máy in và thử lại; đơn đang nhập vẫn được giữ nguyên.',
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_printing,
    child: FormPopup(
      title: widget.data.saved
          ? 'Đơn hàng #${widget.data.invoiceId}'
          : 'Xem trước đơn bán hàng',
      canClose: !_printing,
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: const Color(0xFF176455),
            unselectedLabelColor: const Color(0xFF6E7D83),
            indicatorColor: const Color(0xFF176455),
            dividerColor: Colors.transparent,
            onTap: (index) {
              if (index == 1) _openContract();
            },
            tabs: const [
              Tab(text: 'Hóa đơn'),
              Tab(text: 'Hợp đồng'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _PreviewPane(
                  document: _invoice,
                  printKey: const ValueKey('print-sales-invoice'),
                  printing: _printing,
                  error: _errorTab == 0 ? _error : null,
                  onPrint: _printInvoice,
                  onRetry: () => setState(() {
                    _error = null;
                    _errorTab = null;
                    _invoice = _buildInvoice();
                  }),
                ),
                _PreviewPane(
                  document: _contract,
                  printKey: const ValueKey('print-sale-contract'),
                  printing: _printing,
                  error: _errorTab == 1 ? _error : null,
                  onPrint: _printContract,
                  onRetry: () => setState(() {
                    _error = null;
                    _errorTab = null;
                    _contract = _buildContract();
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.document,
    required this.printKey,
    required this.printing,
    required this.onPrint,
    required this.onRetry,
    this.error,
  });
  final Future<Uint8List>? document;
  final Key printKey;
  final bool printing;
  final String? error;
  final VoidCallback onPrint;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Column(
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: document == null
                ? const SizedBox.shrink()
                : FutureBuilder<Uint8List>(
                    future: document,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Không tạo được bản xem trước.'),
                              TextButton(
                                onPressed: onRetry,
                                child: const Text('Thử lại'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return PdfPreview(
                        key: ValueKey(printKey),
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
                            'Không hiển thị được bản xem trước. Vui lòng thử mở lại.',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          key: printKey,
          heroTag: printKey,
          tooltip: printing ? 'Đang in…' : 'In',
          onPressed: printing ? null : onPrint,
          backgroundColor: const Color(0xFF176455),
          foregroundColor: Colors.white,
          child: printing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.print_outlined),
        ),
      ),
    ],
  );
}
