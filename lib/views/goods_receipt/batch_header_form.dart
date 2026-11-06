import '../../core/formatters/money_input_formatter.dart';
import '../widgets/form_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../controllers/goods_receipt_controller.dart';
import '../../controllers/directory_controller.dart';
import '../../models/directory/directory_models.dart';
import '../directory/directory_picker.dart';
import '../../core/formatters/inventory_formatters.dart';

class BatchHeaderForm extends StatelessWidget {
  const BatchHeaderForm({
    super.key,
    required this.controller,
    required this.onSelectDate,
    required this.directory,
  });
  final GoodsReceiptController controller;
  final DirectoryController directory;
  final VoidCallback onSelectDate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final fields = <Widget>[
        const InputDecorator(
          decoration: InputDecoration(labelText: 'Mã lô'),
          child: Text(
            'Tự cấp khi lưu',
            style: TextStyle(color: Color(0xFF6E7D83)),
          ),
        ),
        TextFormField(
          key: ValueKey('batch-date-${controller.date}'),
          readOnly: true,
          initialValue: DateFormat('dd/MM/yyyy').format(controller.date),
          decoration: const InputDecoration(
            labelText: 'Ngày nhập',
            suffixIcon: Icon(Icons.calendar_today_outlined, size: 19),
          ),
          onTap: onSelectDate,
        ),
        _number(
          'batch-quantity',
          'Số lượng trong lô',
          controller.batch.quantity,
          (v) => controller.updateBatch((d) => d.quantity = v),
          positive: true,
        ),
        _number(
          'batch-total',
          'Tổng tiền lô',
          controller.batch.totalAmount,
          (v) => controller.updateBatch((d) => d.totalAmount = v),
          currency: true,
        ),
        DirectoryPicker(
          directory: directory,
          kind: DirectoryKind.carrier,
          fieldKey: 'batch-delivered-by',
          initialName: controller.batch.deliveredBy,
          selectedId: controller.batch.carrierId,
          onSelected: (entry) =>
              controller.selectBatchCarrier(entry.id, entry.name),
          onTextChanged: controller.changeBatchCarrier,
        ),
        DirectoryPicker(
          directory: directory,
          kind: DirectoryKind.partner,
          fieldKey: 'batch-origin',
          initialName: controller.batch.origin,
          selectedId: controller.batch.partnerId,
          onSelected: (entry) =>
              controller.selectBatchPartner(entry.id, entry.name),
          onTextChanged: controller.changeBatchPartner,
        ),
        _number(
          'batch-paid',
          'Số tiền đã trả',
          controller.batch.paidAmount,
          (v) => controller.updateBatch((d) => d.paidAmount = v),
          currency: true,
        ),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Số tiền còn nợ'),
          child: Text(
            money(controller.batchRemaining),
            style: TextStyle(
              color: controller.batchRemaining < 0
                  ? Theme.of(context).colorScheme.error
                  : const Color(0xFF176455),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ];
      return ResponsiveFormFields(
        fields: fields,
        compact: true,
        columnSpans: const {4: 2, 5: 2},
      );
    },
  );

  Widget _number(
    String key,
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool positive = false,
    bool currency = false,
  }) => TextFormField(
    key: ValueKey(key),
    initialValue: currency ? groupMoney(value) : value,
    decoration: InputDecoration(
      labelText: label,
      suffixText: currency ? 'đ' : null,
    ),
    keyboardType: TextInputType.number,
    inputFormatters: [
      if (currency)
        const MoneyInputFormatter()
      else
        FilteringTextInputFormatter.digitsOnly,
    ],
    validator: (v) {
      final n = int.tryParse(currency ? ungroupMoney(v ?? '') : v ?? '');
      if (n == null || n < 0 || (positive && n == 0)) {
        return positive
            ? 'Số lượng phải lớn hơn 0'
            : 'Vui lòng nhập số tiền hợp lệ';
      }
      return null;
    },
    onChanged: (v) => onChanged(currency ? ungroupMoney(v) : v),
  );
}
