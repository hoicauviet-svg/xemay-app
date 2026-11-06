import '../maintenance/record_line_delete_button.dart';
import '../../models/maintenance/record_maintenance.dart';
import '../maintenance/record_actions.dart';
import '../maintenance/record_recovery_button.dart';
import '../../models/products/product_details.dart';
import '../products/product_details_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../core/formatters/money_input_formatter.dart';
import '../../services/payment_document_service.dart';
import 'package:intl/intl.dart';
import '../../controllers/batch_details_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/batches/batch_models.dart';
import '../../models/goods_receipt/goods_receipt_models.dart';
import '../../models/repositories/batch_repository.dart';
import '../../models/repositories/directory_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_popup.dart';
import '../widgets/scrollable_data_table.dart';
import '../goods_receipt/goods_receipt_form_screen.dart';

class BatchDetailsScreen extends StatefulWidget {
  const BatchDetailsScreen({
    super.key,
    required this.batch,
    required this.type,
    required this.repository,
    this.directoryRepository,
    this.pickDocuments,
  });
  final ReceiptBatch batch;
  final ReceiptProductType type;
  final BatchRepository repository;
  final DirectoryRepository? directoryRepository;
  final Future<List<PaymentDocument>> Function()? pickDocuments;
  @override
  State<BatchDetailsScreen> createState() => _BatchDetailsScreenState();
}

class _BatchDetailsScreenState extends State<BatchDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final BatchDetailsController _controller;
  late final TabController _tabs;
  int _activeIndex = 0;
  final _paymentFormKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final List<PaymentDocument> _documents = [];
  bool _saving = false, _choosingDocuments = false;
  String _paymentRequestId = ObjectId().oid;
  BatchPaymentPreview? _pendingPayment;
  dynamic _selectedPayment;
  bool _deletePayment = false;
  void _choosePayment(dynamic id, bool deleting) {
    setState(() {
      _selectedPayment = id;
      _deletePayment = deleting;
    });
    _tabs.animateTo(0);
  }

  void _clearPayment() {
    setState(() {
      _selectedPayment = null;
      _deletePayment = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = BatchDetailsController(
      widget.repository,
      widget.batch,
      widget.type,
    );
    _tabs = TabController(length: BatchDetailTab.values.length, vsync: this);
    _tabs.addListener(_tabChanged);
    unawaited(_controller.load());
  }

  void _tabChanged() {
    if (_activeIndex != _tabs.index) setState(() => _activeIndex = _tabs.index);
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    _controller.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Scaffold(
      appBar: AppTopBar(
        title: 'Lô hàng #${widget.batch.id}',
        actions: [
          RecordRecoveryButton(
            repository: widget.repository.maintenance,
            onChanged: _controller.load,
          ),
        ],
      ),
      floatingActionButton:
          _activeIndex == BatchDetailTab.products.index &&
              !_controller.loading &&
              _controller.error == null
          ? FloatingActionButton(
              tooltip: 'Thêm sản phẩm vào lô',
              onPressed: _addProduct,
              backgroundColor: const Color(0xFF176455),
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5EAED)),
              ),
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: const Color(0xFF176455),
                unselectedLabelColor: const Color(0xFF6E7D83),
                indicatorColor: const Color(0xFF176455),
                dividerColor: Colors.transparent,
                tabs: [
                  for (final tab in BatchDetailTab.values) Tab(text: tab.label),
                ],
                onTap: (_) => FocusScope.of(context).unfocus(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _ready(_information),
                  _content(),
                  _ready(_history),
                  _ready(_paymentForm),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _addProduct() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FormPopup(
        title: 'Thêm sản phẩm vào lô #${_controller.batch.id}',
        child: GoodsReceiptFormScreen(
          type: widget.type,
          existingBatch: _controller.batch,
          directoryRepository: widget.directoryRepository,
          embedded: true,
        ),
      ),
    );
    if (mounted) await _controller.load();
  }

  Widget _ready(Widget Function() content) {
    if (_controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_controller.error!, textAlign: TextAlign.center),
            TextButton(
              onPressed: _controller.load,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    return content();
  }

  Widget _information() {
    if (widget.repository.maintenance != null && true) {
      return RecordEditor(
        key: ValueKey('inline:$_selectedPayment:$_deletePayment'),
        repository: widget.repository.maintenance!,
        kind: RecordKind.batch,
        id: widget.batch.id,
        paymentId: _selectedPayment,
        deleting: _selectedPayment != null && _deletePayment,
        embedded: true,
        onSaved: () async {
          _clearPayment();
          await _controller.load();
        },
        onDeleted: () => Navigator.pop(context),
        onCancel: _selectedPayment == null ? null : _clearPayment,
      );
    }

    final batch = _controller.batch;
    final fields = <(String, String)>[
      ('Mã lô', '#${batch.id}'),
      (
        'Ngày nhập',
        batch.date == null ? '—' : DateFormat('dd/MM/yyyy').format(batch.date!),
      ),
      ('Vận chuyển', batch.deliveredBy.isEmpty ? '—' : batch.deliveredBy),
      ('Đối tác / nhà cung cấp', batch.origin.isEmpty ? '—' : batch.origin),
      (
        'Số lượng khai báo',
        batch.quantity == null ? '—' : quantity(batch.quantity!),
      ),
      ('Sản phẩm liên kết', quantity(_controller.products.length)),
      ('Tổng tiền', money(batch.total)),
      ('Đã trả', money(batch.paid)),
      ('Còn nợ', money(batch.remaining)),
    ];
    return _panel(
      SingleChildScrollView(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final columns = bounds.maxWidth >= 640 ? 2 : 1;
            final width = (bounds.maxWidth - (columns - 1) * 20) / columns;
            return Wrap(
              spacing: 20,
              runSpacing: 24,
              children: [
                for (final field in fields)
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field.$1,
                          style: const TextStyle(
                            color: Color(0xFF6E7D83),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          field.$2,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _history() {
    if (_controller.payments.isEmpty) {
      return const Center(child: Text('Lô hàng chưa có lịch sử thanh toán.'));
    }
    return ScrollableDataTable(
      columns: const [
        DataColumn(label: Text('MÃ THANH TOÁN')),
        DataColumn(label: Text('NGÀY THANH TOÁN')),
        DataColumn(label: Text('SỐ TIỀN TRẢ')),
        DataColumn(label: Text('CÒN NỢ SAU LẦN TRẢ')),
        DataColumn(label: Text('CHỨNG TỪ')),
        DataColumn(label: Text('GHI CHÚ')),
        DataColumn(label: Text('')),
      ],
      rows: [
        for (final payment in _controller.payments)
          DataRow(
            cells: [
              DataCell(Text('#${payment.id}')),
              DataCell(
                Text(
                  payment.date == null
                      ? '—'
                      : DateFormat('dd/MM/yyyy').format(payment.date!),
                ),
              ),
              DataCell(Text(money(payment.amount))),
              DataCell(Text(money(payment.remaining))),
              DataCell(
                payment.documents.isEmpty
                    ? const Text('')
                    : TextButton.icon(
                        onPressed: () => _showDocuments(payment),
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: Text('${payment.documents.length} file'),
                      ),
              ),
              DataCell(
                SizedBox(
                  width: 260,
                  child: Text(
                    payment.notes.isEmpty ? '—' : payment.notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                RecordActions(
                  repository: widget.repository.maintenance,
                  kind: RecordKind.batch,
                  id: widget.batch.id,
                  paymentId: payment.id,
                  onSelect: (deleting) => _choosePayment(payment.id, deleting),
                  onChanged: _controller.load,
                ),
              ),
            ],
          ),
      ],
    );
  }

  bool get _canEditPayment =>
      !_saving && !_choosingDocuments && _pendingPayment == null;
  Future<void> _chooseDocuments() async {
    if (!_canEditPayment) return;
    setState(() => _choosingDocuments = true);
    try {
      final files =
          await (widget.pickDocuments ?? PaymentDocumentService.pick)();
      if (!mounted) return;
      if (_documents.length + files.length > 10 ||
          [
                ..._documents,
                ...files,
              ].fold<int>(0, (sum, d) => sum + d.bytes.length) >
              PaymentDocument.maxTotalBytes) {
        throw const BatchPaymentException(
          'Tối đa 10 file, tổng dung lượng tối đa 8 MB.',
        );
      }
      setState(() => _documents.addAll(files));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is BatchPaymentException
                  ? e.message
                  : 'Chưa chọn được chứng từ. Vui lòng thử lại.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _choosingDocuments = false);
    }
  }

  Future<void> _savePayment() async {
    if (_saving || _choosingDocuments) return;
    if (_pendingPayment == null) {
      if (!_paymentFormKey.currentState!.validate()) return;
      final error = _controller.validatePayment();
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
      _pendingPayment = _controller.previewPayment(documents: _documents);
    }
    setState(() => _saving = true);
    try {
      await widget.repository.pay(
        _pendingPayment!,
        requestId: _paymentRequestId,
      );
      if (!mounted) return;
      _amount.clear();
      _notes.clear();
      _controller.setPaymentAmount('');
      _controller.setPaymentNotes('');
      setState(() {
        _documents.clear();
        _pendingPayment = null;
        _paymentRequestId = ObjectId().oid;
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Thanh toán thành công')));
      _tabs.animateTo(BatchDetailTab.paymentHistory.index);
      await _controller.load();
    } on BatchPaymentException catch (e) {
      if (mounted) {
        setState(() => _pendingPayment = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Chưa xác nhận thanh toán. Bấm Thanh toán để thử lại lần này.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDocumentCopy(PaymentDocument document) async {
    try {
      final saved = await PaymentDocumentService.saveCopy(document);
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu chứng từ')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa lưu được chứng từ. Vui lòng thử lại.'),
          ),
        );
      }
    }
  }

  void _showDocuments(BatchPayment payment) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Chứng từ thanh toán #${payment.id}'),
      content: SizedBox(
        width: 600,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final document in payment.documents)
              ListTile(
                leading: Icon(
                  document.mimeType == 'application/pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                ),
                title: Text(
                  document.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${(document.bytes.length / 1024).toStringAsFixed(0)} KB',
                ),
                trailing: IconButton(
                  tooltip: 'Lưu bản sao',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => _saveDocumentCopy(document),
                ),
                onTap: () => document.mimeType.startsWith('image/')
                    ? showDialog<void>(
                        context: context,
                        builder: (context) => Dialog(
                          child: SizedBox(
                            width: 800,
                            height: 600,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(document.name),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Đóng',
                                      onPressed: () => Navigator.pop(context),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: InteractiveViewer(
                                    child: Image.memory(
                                      document.bytes,
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Text(
                                          'Không hỗ trợ xem trước ảnh này. Hãy lưu bản sao để mở trên máy.',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : _saveDocumentCopy(document),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );

  Future<void> _selectPaymentDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _controller.paymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (value != null && mounted) _controller.setPaymentDate(value);
  }

  void _previewPayment() {
    if (!_paymentFormKey.currentState!.validate()) return;
    final error = _controller.validatePayment();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final preview = _controller.previewPayment(documents: _documents);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xem trước thanh toán'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lô hàng #${preview.batchId}'),
            const SizedBox(height: 12),
            Text(
              'Ngày thanh toán: ${DateFormat('dd/MM/yyyy').format(preview.date)}',
            ),
            Text('Số tiền: ${money(preview.amount)}'),
            if (preview.notes.isNotEmpty) Text('Ghi chú: ${preview.notes}'),
            for (final document in preview.documents)
              Text('Chứng từ: ${document.name}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tiếp tục chỉnh sửa'),
          ),
        ],
      ),
    );
  }

  Widget _paymentForm() => _panel(
    SingleChildScrollView(
      child: Form(
        key: _paymentFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tổng nợ: ${money(_controller.batch.remaining)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF176455),
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              key: const ValueKey('batch-payment-amount'),
              controller: _amount,
              enabled: _canEditPayment,
              decoration: const InputDecoration(
                labelText: 'Số tiền thanh toán',
                suffixText: 'đ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [const MoneyInputFormatter()],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) =>
                  _controller.paymentAmountError(ungroupMoney(v ?? '')),
              onChanged: (value) =>
                  _controller.setPaymentAmount(ungroupMoney(value)),
            ),
            const SizedBox(height: 20),
            InputDecorator(
              key: const ValueKey('batch-payment-remaining'),
              decoration: const InputDecoration(labelText: 'Còn nợ'),
              child: Text(
                _controller.remainingAfterPayment == null
                    ? ''
                    : money(_controller.remainingAfterPayment),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: ValueKey('payment-date-${_controller.paymentDate}'),
              readOnly: true,
              initialValue: DateFormat(
                'dd/MM/yyyy',
              ).format(_controller.paymentDate),
              decoration: const InputDecoration(
                labelText: 'Ngày thanh toán',
                suffixIcon: Icon(Icons.calendar_today_outlined, size: 19),
              ),
              onTap: _canEditPayment ? _selectPaymentDate : null,
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('batch-payment-notes'),
              controller: _notes,
              enabled: _canEditPayment,
              maxLength: 10000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
              onChanged: _controller.setPaymentNotes,
            ),
            const SizedBox(height: 20),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Chứng từ'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _canEditPayment ? _chooseDocuments : null,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _choosingDocuments ? 'Đang chọn…' : 'Chọn ảnh hoặc PDF',
                    ),
                  ),
                  const Text(
                    'Tối đa 10 file, tổng dung lượng 8 MB.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
                  ),
                  for (final document in _documents)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            document.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Bỏ chứng từ',
                          onPressed: _canEditPayment
                              ? () =>
                                    setState(() => _documents.remove(document))
                              : null,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed:
                      !_saving &&
                          !_choosingDocuments &&
                          (_controller.batch.remaining ?? 0) > 0
                      ? _savePayment
                      : null,
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(_saving ? 'Đang lưu…' : 'Thanh toán'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving || _choosingDocuments
                      ? null
                      : _previewPayment,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Xem phiếu thanh toán'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5EAED)),
    ),
    child: child,
  );

  Widget _content() {
    if (_controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_controller.error!, textAlign: TextAlign.center),
            TextButton(
              onPressed: _controller.load,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    if (_controller.products.isEmpty) {
      return const Center(child: Text('Lô hàng chưa có sản phẩm liên kết.'));
    }
    return ScrollableDataTable(
      fixedHeader: true,
      columnWidths: const [160, 240, 100, 180, 180, 140, 160, 64],
      columns: const [
        DataColumn(label: Text('MÃ XE / SẢN PHẨM')),
        DataColumn(label: Text('TÊN SẢN PHẨM')),
        DataColumn(label: Text('SỐ LƯỢNG')),
        DataColumn(label: Text('SỐ KHUNG')),
        DataColumn(label: Text('SỐ MÁY')),
        DataColumn(label: Text('BIỂN SỐ')),
        DataColumn(label: Text('GIÁ NHẬP')),
        DataColumn(label: Text('')),
      ],
      rows: [
        for (final item in _controller.products)
          DataRow(
            onSelectChanged: (_) async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ProductDetailsScreen(
                    product: ProductReference(
                      id: item.vehicleId ?? item.productId,
                      vehicle: item.vehicleId != null,
                    ),
                  ),
                ),
              );
              if (mounted) await _controller.load();
            },
            cells: [
              DataCell(Text('#${item.vehicleId ?? item.productId}')),
              DataCell(
                SizedBox(
                  width: 200,
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(Text(quantity(item.quantity))),
              DataCell(Text(item.frameNumber.isEmpty ? '—' : item.frameNumber)),
              DataCell(
                Text(item.engineNumber.isEmpty ? '—' : item.engineNumber),
              ),
              DataCell(Text(item.plate.isEmpty ? '—' : item.plate)),
              DataCell(Text(money(item.cost))),
              DataCell(
                RecordLineDeleteButton(
                  repository: widget.repository.maintenance,
                  kind: RecordKind.batch,
                  parentId: widget.batch.id,
                  lineId: item.sourceId,
                  onChanged: _controller.load,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
