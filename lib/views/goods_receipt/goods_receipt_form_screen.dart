import '../../core/formatters/money_input_formatter.dart';
import 'dart:async';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../services/mongo_receipt_repository.dart';
import '../../models/repositories/receipt_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../controllers/goods_receipt_controller.dart';
import '../../controllers/directory_controller.dart';
import '../../models/directory/directory_models.dart';
import '../../models/repositories/directory_repository.dart';
import '../../services/mongo_directory_repository.dart';
import '../directory/directory_picker.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/goods_receipt/goods_receipt_models.dart';
import '../../models/batches/batch_models.dart';
import 'batch_header_form.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_section.dart';

const _muted = Color(0xFF6E7D83), _green = Color(0xFF176455);

class GoodsReceiptFormScreen extends StatefulWidget {
  const GoodsReceiptFormScreen({
    super.key,
    required this.type,
    this.initialMode = ReceiptMode.single,
    this.embedded = false,
    this.existingBatch,
    this.directoryRepository,
    this.receiptRepository,
  });
  final ReceiptProductType type;
  final ReceiptMode initialMode;
  final bool embedded;
  final ReceiptBatch? existingBatch;
  final DirectoryRepository? directoryRepository;
  final ReceiptRepository? receiptRepository;
  @override
  State<GoodsReceiptFormScreen> createState() => _GoodsReceiptFormScreenState();
}

class _GoodsReceiptFormScreenState extends State<GoodsReceiptFormScreen> {
  late final GoodsReceiptController _controller;
  late final DirectoryController _directory;
  late final ReceiptRepository _receiptRepository;
  final _requestId = ObjectId().oid;
  ReceiptPreview? _pendingReceipt;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final TextEditingController _paidController;

  @override
  void initState() {
    super.initState();
    _receiptRepository = widget.receiptRepository ?? MongoReceiptRepository();
    _directory = DirectoryController(
      widget.directoryRepository ?? MongoDirectoryRepository(),
    );
    _controller = GoodsReceiptController(
      widget.type,
      targetBatchId: widget.existingBatch?.id,
      directoryRepository: _directory.repository,
    );
    if (widget.existingBatch?.date != null) {
      _controller.date = widget.existingBatch!.date!;
    }
    if (widget.existingBatch != null) {
      _controller.partner = widget.existingBatch!.origin;
    }
    _controller.setMode(widget.initialMode);
    _paidController = TextEditingController(
      text: groupMoney(_controller.paidAmount),
    );
    _controller.addListener(_syncPaidAmount);
  }

  void _syncPaidAmount() {
    final text = groupMoney(_controller.paidAmount);
    if (_paidController.text != text) {
      _paidController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_receiptRepository.close());
    _controller.removeListener(_syncPaidAmount);
    _paidController.dispose();
    _controller.dispose();
    _directory.dispose();
    if (widget.directoryRepository == null) {
      unawaited(_directory.repository.close());
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _controller.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date != null && mounted) _controller.setDate(date);
  }

  void _continueBatch() {
    if (!_formKey.currentState!.validate()) return;
    final error = _controller.confirmBatch();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_pendingReceipt == null) {
      if (!_formKey.currentState!.validate()) return;
      final error = _controller.validate();
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
      _pendingReceipt = _controller.preview();
    }
    setState(() => _saving = true);
    try {
      await _receiptRepository.save(_pendingReceipt!, _requestId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(const SnackBar(content: Text('Nhập thành công')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa hoàn tất lưu. Bấm Lưu để thử lại phiếu này.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _preview() {
    if (!_formKey.currentState!.validate()) return;
    final error = _controller.validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final receipt = _controller.preview();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xem trước phiếu nhập'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt.batchId == null
                      ? '${receipt.type.title} · ${receipt.mode == ReceiptMode.batch ? 'Nhập lô' : 'Nhập lẻ'}'
                      : 'Thêm sản phẩm vào lô #${receipt.batchId}',
                ),
                const SizedBox(height: 12),
                Text(
                  'Ngày nhập: ${receipt.batchId != null && widget.existingBatch?.date == null ? 'Chưa ghi nhận' : DateFormat('dd/MM/yyyy').format(receipt.date)}',
                ),
                if (receipt.partner.isNotEmpty)
                  Text('Đối tác / nhà cung cấp: ${receipt.partner}'),
                if (receipt.mode == ReceiptMode.single &&
                    receipt.batchId == null) ...[
                  Text(
                    'Vận chuyển: ${receipt.carrier.isEmpty ? 'Tự nhận hàng' : receipt.carrier}',
                  ),
                  Text(
                    'Đã trả: ${money(receipt.paidAmount)} · Còn nợ: ${money(receipt.remainingAmount)}',
                  ),
                ],
                if (receipt.batchInfo case final batch?) ...[
                  Text('Vận chuyển: ${batch.deliveredBy}'),
                  Text('Số lượng khai báo: ${quantity(batch.quantity)}'),
                  Text('Tổng tiền lô: ${money(batch.totalAmount)}'),
                  Text(
                    'Đã trả: ${money(batch.paidAmount)} · Còn nợ: ${money(batch.remainingAmount)}',
                  ),
                ],
                const Divider(height: 28),
                for (final line in receipt.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${quantity(line.quantity)} × ${money(line.unitPrice)} = ${money(line.amount)}',
                        ),

                        if (line.productCode.isNotEmpty)
                          Text('Mã sản phẩm: ${line.productCode}'),
                        Text('Đơn vị tính: ${line.unit}'),
                        if (line.salePrice != null)
                          Text('Giá bán: ${money(line.salePrice)}'),
                        Text('Tổng chi phí: ${money(line.totalCosts)}'),
                        if (line.vehicleNotes.isNotEmpty)
                          Text('Ghi chú xe: ${line.vehicleNotes}'),
                        if (line.frameNumber.isNotEmpty)
                          Text('Số khung: ${line.frameNumber}'),
                        if (line.engineNumber.isNotEmpty)
                          Text('Số máy: ${line.engineNumber}'),
                        if (line.plate.isNotEmpty)
                          Text('Biển số: ${line.plate}'),
                      ],
                    ),
                  ),
                const Divider(),
                Text(
                  'Tổng tiền: ${money(receipt.total)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _green,
                  ),
                ),
                if (receipt.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Ghi chú: ${receipt.notes}'),
                ],
              ],
            ),
          ),
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Scaffold(
      appBar: widget.embedded
          ? null
          : AppTopBar(
              title: widget.existingBatch != null
                  ? 'Thêm sản phẩm vào lô #${widget.existingBatch!.id}'
                  : widget.initialMode == ReceiptMode.batch
                  ? 'Nhập lô hàng'
                  : widget.type.title,
            ),
      body: AbsorbPointer(
        absorbing: _pendingReceipt != null,
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (widget.existingBatch != null)
                      _section('Lô hàng #${widget.existingBatch!.id}', [
                        Text(
                          'Đối tác / nhà cung cấp: ${widget.existingBatch!.origin.isEmpty ? '—' : widget.existingBatch!.origin}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ngày nhập của lô: ${widget.existingBatch!.date == null ? 'Chưa ghi nhận' : DateFormat('dd/MM/yyyy').format(widget.existingBatch!.date!)}',
                        ),
                      ])
                    else if (_controller.mode == ReceiptMode.single)
                      _section('Thông tin phiếu nhập', [
                        _fields([
                          DirectoryPicker(
                            directory: _directory,
                            kind: DirectoryKind.partner,
                            fieldKey: 'receipt-partner',
                            requiredSelection: false,
                            initialName: _controller.partner,
                            selectedId: _controller.partnerId,
                            onSelected: (entry) =>
                                _controller.selectPartner(entry.id, entry.name),
                            onTextChanged: _controller.changePartner,
                          ),
                          TextFormField(
                            key: ValueKey(_controller.date),
                            readOnly: true,
                            initialValue: DateFormat(
                              'dd/MM/yyyy',
                            ).format(_controller.date),
                            decoration: const InputDecoration(
                              labelText: 'Ngày nhập',
                              suffixIcon: Icon(
                                Icons.calendar_today_outlined,
                                size: 19,
                              ),
                            ),
                            onTap: _selectDate,
                          ),
                          DirectoryPicker(
                            directory: _directory,
                            kind: DirectoryKind.carrier,
                            fieldKey: 'receipt-carrier',
                            requiredSelection: false,
                            initialName: _controller.carrier,
                            selectedId: _controller.carrierId,
                            onSelected: (entry) =>
                                _controller.selectCarrier(entry.id, entry.name),
                            onTextChanged: _controller.changeCarrier,
                          ),
                          TextFormField(
                            initialValue: _controller.notes,
                            decoration: const InputDecoration(
                              labelText: 'Ghi chú',
                            ),
                            onChanged: (value) => _controller.notes = value,
                          ),
                        ]),
                      ])
                    else if (!_controller.isBatchConfirmed)
                      _section('Thông tin lô nhập', [
                        BatchHeaderForm(
                          controller: _controller,
                          directory: _directory,
                          onSelectDate: _selectDate,
                        ),
                      ])
                    else
                      _batchSummary(),
                    const SizedBox(height: 20),
                    if (_controller.showProductForm) ...[
                      for (var i = 0; i < _controller.lines.length; i++) ...[
                        _line(_controller.lines[i], i),
                        const SizedBox(height: 16),
                      ],
                      if (_controller.mode == ReceiptMode.single &&
                          widget.existingBatch == null)
                        _section('Thanh toán', [
                          _fields([
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Tổng tiền nhập',
                              ),
                              child: Text(money(_controller.total)),
                            ),
                            TextFormField(
                              key: const ValueKey('receipt-paid'),
                              controller: _paidController,
                              decoration: const InputDecoration(
                                labelText: 'Số tiền đã trả',
                                suffixText: 'đ',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [const MoneyInputFormatter()],
                              validator: (v) => _controller.singlePaymentError(
                                ungroupMoney(v ?? ''),
                              ),
                              onChanged: (v) =>
                                  _controller.setPaidAmount(ungroupMoney(v)),
                            ),
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Số tiền còn nợ',
                              ),
                              child: Text(
                                money(_controller.singleRemaining),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _controller.singleRemaining < 0
                                      ? Theme.of(context).colorScheme.error
                                      : _green,
                                ),
                              ),
                            ),
                          ]),
                        ]),
                      if (_controller.mode == ReceiptMode.batch)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _controller.canAddLine
                                ? _controller.addLine
                                : null,
                            icon: const Icon(Icons.add),
                            label: Text(
                              widget.type.isVehicle
                                  ? 'Thêm xe'
                                  : 'Thêm mặt hàng',
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _footer(),
    ),
  );

  Widget _batchSummary() {
    final batch = _controller.batchInfo;
    return _section('Thông tin lô nhập', [
      Wrap(
        spacing: 24,
        runSpacing: 10,
        children: [
          Text('Ngày nhập: ${DateFormat('dd/MM/yyyy').format(batch.date)}'),
          Text('Vận chuyển: ${batch.deliveredBy}'),
          Text('Đối tác / nhà cung cấp: ${batch.origin}'),
          Text('Số lượng lô: ${quantity(batch.quantity)}'),
          Text('Tổng tiền lô: ${money(batch.totalAmount)}'),
          Text('Đã trả: ${money(batch.paidAmount)}'),
          Text('Còn nợ: ${money(batch.remainingAmount)}'),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              'Đã kê ${quantity(_controller.totalQuantity)} / ${quantity(batch.quantity)} ${widget.type.isVehicle ? 'xe' : 'sản phẩm'}',
              style: const TextStyle(color: _muted),
            ),
          ),
          TextButton.icon(
            onPressed: _controller.editBatch,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Sửa thông tin lô'),
          ),
        ],
      ),
    ]);
  }

  Widget _section(String title, List<Widget> children) =>
      FormSection(title: title, children: children);

  Widget _fields(List<Widget> fields) =>
      ResponsiveFormFields(fields: fields, compact: true);

  Widget _line(ReceiptLineDraft line, int index) => Container(
    key: ValueKey('receipt-line-${line.id}'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5EAED)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_controller.mode == ReceiptMode.batch &&
            _controller.lines.length > 1)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Xóa dòng',
              onPressed: () => _controller.removeLine(line),
              icon: const Icon(Icons.delete_outline, color: _muted),
            ),
          ),
        _fields([
          TextFormField(
            key: ValueKey('line-name-${line.id}'),
            initialValue: line.name,
            decoration: InputDecoration(
              labelText: widget.type.isVehicle ? 'Tên xe' : 'Tên phụ tùng',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Vui lòng nhập tên'
                : null,
            onChanged: (value) =>
                _controller.updateLine(line, (draft) => draft.name = value),
          ),
          if (!widget.type.isVehicle) ...[
            TextFormField(
              key: ValueKey('line-code-${line.id}'),
              initialValue: line.productCode,
              decoration: const InputDecoration(
                labelText: 'Mã sản phẩm',
                hintText: 'Mã nếu đã có',
              ),
              onChanged: (v) =>
                  _controller.updateLine(line, (d) => d.productCode = v),
            ),
            TextFormField(
              key: ValueKey('line-unit-${line.id}'),
              initialValue: line.unit,
              decoration: const InputDecoration(labelText: 'Đơn vị tính'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Vui lòng nhập đơn vị tính'
                  : null,
              onChanged: (v) => _controller.updateLine(line, (d) => d.unit = v),
            ),
          ],
          if (!widget.type.isVehicle)
            TextFormField(
              key: ValueKey('line-quantity-${line.id}'),
              initialValue: line.quantity,
              decoration: const InputDecoration(labelText: 'Số lượng'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) => (int.tryParse(value ?? '') ?? 0) <= 0
                  ? 'Số lượng phải lớn hơn 0'
                  : null,
              onChanged: (value) => _controller.updateLine(
                line,
                (draft) => draft.quantity = value,
              ),
            ),
          TextFormField(
            key: ValueKey('line-price-${line.id}'),
            initialValue: groupMoney(line.unitPrice),
            decoration: const InputDecoration(
              labelText: 'Giá nhập',
              suffixText: 'đ',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [const MoneyInputFormatter()],
            validator: (value) =>
                int.tryParse(ungroupMoney(value ?? '')) == null ||
                    int.parse(ungroupMoney(value ?? '')) < 0
                ? 'Vui lòng nhập giá không âm'
                : null,
            onChanged: (value) => _controller.updateLine(
              line,
              (draft) => draft.unitPrice = ungroupMoney(value),
            ),
          ),
          TextFormField(
            key: ValueKey('line-sale-price-${line.id}'),
            initialValue: groupMoney(line.salePrice),
            decoration: const InputDecoration(
              labelText: 'Giá bán',
              suffixText: 'đ',
              hintText: 'Để trống nếu chưa xác định',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [const MoneyInputFormatter()],
            validator: (v) => GoodsReceiptController.optionalMoneyError(
              ungroupMoney(v ?? ''),
            ),
            onChanged: (v) => _controller.updateLine(
              line,
              (d) => d.salePrice = ungroupMoney(v),
            ),
          ),
          if (widget.type == ReceiptProductType.newVehicle) ...[
            TextFormField(
              key: ValueKey('line-frame-${line.id}'),
              initialValue: line.frameNumber,
              decoration: const InputDecoration(labelText: 'Số khung'),
              onChanged: (value) => _controller.updateLine(
                line,
                (draft) => draft.frameNumber = value,
              ),
            ),
            TextFormField(
              key: ValueKey('line-engine-${line.id}'),
              initialValue: line.engineNumber,
              decoration: const InputDecoration(labelText: 'Số máy'),
              onChanged: (value) => _controller.updateLine(
                line,
                (draft) => draft.engineNumber = value,
              ),
            ),
          ],
          if (widget.type.isVehicle) ...[
            TextFormField(
              key: ValueKey('line-plate-${line.id}'),
              initialValue: line.plate,
              decoration: const InputDecoration(labelText: 'Biển số'),
              onChanged: (value) =>
                  _controller.updateLine(line, (draft) => draft.plate = value),
            ),
          ],
        ]),
        if (widget.type == ReceiptProductType.usedVehicle) ...[
          const SizedBox(height: 20),
          TextFormField(
            key: ValueKey('line-vehicle-notes-${line.id}'),
            initialValue: line.vehicleNotes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Ghi chú xe'),
            onChanged: (v) =>
                _controller.updateLine(line, (d) => d.vehicleNotes = v),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Chi phí được nhập tại trang chi tiết sản phẩm.',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        if (widget.type.isVehicle)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Số lượng: 1 chiếc · Tình trạng bán hàng: Chưa bán',
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Thành tiền: ${money(_controller.amountOf(line))}',
          style: const TextStyle(fontWeight: FontWeight.w600, color: _green),
        ),
      ],
    ),
  );

  Widget _footer() => Material(
    color: Colors.white,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final enteringBatch =
                _controller.mode == ReceiptMode.batch &&
                !_controller.isBatchConfirmed;
            final totals = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  enteringBatch
                      ? 'Số lượng lô: ${quantity(_controller.batchQuantity)}'
                      : '${widget.type.isVehicle ? 'Số xe' : 'Số lượng'}: ${quantity(_controller.totalQuantity)}',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                Text(
                  enteringBatch
                      ? 'Tổng tiền lô: ${money(_controller.batchTotal)}'
                      : 'Tổng tiền: ${money(_controller.total)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _green,
                  ),
                ),
              ],
            );
            final actions = Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                const SizedBox(width: 12),
                if (!enteringBatch) ...[
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(_saving ? 'Đang lưu…' : 'Lưu'),
                  ),
                  const SizedBox(width: 12),
                ],
                FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : (enteringBatch ? _continueBatch : _preview),
                  icon: Icon(
                    enteringBatch
                        ? Icons.arrow_forward
                        : Icons.receipt_long_outlined,
                    size: 18,
                  ),
                  label: Text(enteringBatch ? 'Tiếp tục' : 'Xem phiếu nhập'),
                ),
              ],
            );
            if (bounds.maxWidth < 650) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  totals,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: totals),
                actions,
              ],
            );
          },
        ),
      ),
    ),
  );
}
