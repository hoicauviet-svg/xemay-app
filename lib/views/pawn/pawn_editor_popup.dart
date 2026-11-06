import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../core/formatters/money_input_formatter.dart';
import '../../models/pawn/pawn_models.dart';
import '../../models/repositories/customer_repository.dart';
import '../../models/repositories/pawn_repository.dart';
import '../widgets/form_popup.dart';
import '../customers/customer_editor_popup.dart';
import '../widgets/form_section.dart';

class PawnEditorPopup extends StatefulWidget {
  const PawnEditorPopup({
    super.key,
    required this.repository,
    required this.customers,
  });
  final PawnRepository repository;
  final CustomerRepository customers;
  @override
  State<PawnEditorPopup> createState() => _PawnEditorPopupState();
}

class _PawnEditorPopupState extends State<PawnEditorPopup> {
  final _draft = PawnDraft();
  final _customerText = TextEditingController();
  final _customerFocus = FocusNode();
  final _form = GlobalKey<FormState>();
  final _requestId = ObjectId().oid;
  PawnDraft? _submitted;
  bool _saving = false;
  String? _error;
  bool get _editable => !_saving && _submitted == null;
  @override
  void dispose() {
    _customerText.dispose();
    _customerFocus.dispose();
    super.dispose();
  }

  Future<void> _addCustomer() async {
    if (!_editable) return;
    _customerFocus.unfocus();
    final customer = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerEditorPopup(onCreate: widget.customers.create),
    );
    if (customer == null || !mounted) return;
    setState(() {
      _draft.customerId = (customer['IdKH'] as num).toInt();
      _customerText.text = '${customer['TenKhachHang'] ?? ''}';
    });
    _customerFocus.unfocus();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_submitted == null) {
      if (!_form.currentState!.validate()) return;
      final error = _draft.validate();
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      _submitted = _draft.snapshot();
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.repository.create(
        _submitted!,
        requestId: _requestId,
      );
      if (mounted) Navigator.pop(context, id);
    } on PawnException catch (e) {
      if (mounted) {
        setState(() {
          _submitted = null;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Chưa xác nhận lưu phiếu. Bấm Lưu để thử lại phiếu này.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseDate(bool due) async {
    final date = await showDatePicker(
      context: context,
      initialDate: due ? (_draft.dueDate ?? _draft.loanDate) : _draft.loanDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2079, 6, 6),
    );
    if (date != null && mounted) {
      setState(() {
        if (due) {
          _draft.dueDate = date;
        } else {
          _draft.loanDate = date;
        }
      });
    }
  }

  Widget _customerPicker() => RawAutocomplete<Map<String, dynamic>>(
    textEditingController: _customerText,
    focusNode: _customerFocus,
    displayStringForOption: (r) => '${r['TenKhachHang'] ?? ''}',
    optionsBuilder: (value) async {
      if (value.text.trim().isEmpty) return const [];
      return (await widget.customers.fetch(search: value.text.trim())).rows;
    },
    onSelected: (row) => setState(() {
      _draft.customerId = (row['IdKH'] as num).toInt();
    }),
    fieldViewBuilder: (context, text, focus, submit) {
      final style = Theme.of(context).textTheme.bodyLarge!;
      final painter = TextPainter(
        text: TextSpan(text: ' ', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final lineHeight = painter.preferredLineHeight;
      painter.dispose();
      final height = (lineHeight + 24).clamp(48.0, double.infinity);
      return Theme(
        data: Theme.of(context).copyWith(visualDensity: VisualDensity.standard),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('pawn-customer'),
                controller: text,
                focusNode: focus,
                enabled: _editable,
                style: style,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: 'Khách hàng',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: (height - lineHeight) / 2,
                  ),
                ),
                validator: (_) => _draft.customerId == null
                    ? 'Vui lòng chọn khách hàng'
                    : null,
                onChanged: (_) => setState(() {
                  _draft.customerId = null;
                }),
                onFieldSubmitted: (_) => submit(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: height,
              height: height,
              child: IconButton.filled(
                key: const ValueKey('pawn-customer-add'),
                tooltip: 'Thêm khách hàng',
                onPressed: _editable ? _addCustomer : null,
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  fixedSize: Size.square(height),
                  minimumSize: Size.square(height),
                  maximumSize: Size.square(height),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
    optionsViewBuilder: (context, select, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 80).clamp(180.0, 500.0),
          height: 240,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final row in options)
                ListTile(
                  key: ValueKey('pawn-customer-option-${row['IdKH']}'),
                  title: Text('${row['TenKhachHang'] ?? ''}'),
                  subtitle: Text(
                    '#${row['IdKH']} · ${row['SoDienThoai'] ?? ''}',
                  ),
                  onTap: () => select(row),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: FormPopup(
      title: 'Thêm phiếu cầm đồ',
      canClose: !_saving,
      child: Scaffold(
        body: Form(
          key: _form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FormSection(
              title: null,
              children: [
                ResponsiveFormFields(
                  compact: true,
                  columnSpans: const {0: 2},
                  fields: [
                    _customerPicker(),
                    TextFormField(
                      key: const ValueKey('pawn-amount'),
                      enabled: _editable,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền vay',
                        suffixText: 'đ',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [const MoneyInputFormatter()],
                      validator: (v) =>
                          (int.tryParse(ungroupMoney(v ?? '')) ?? 0) <= 0
                          ? 'Nhập số tiền lớn hơn 0'
                          : null,
                      onChanged: (v) => _draft.amount = ungroupMoney(v),
                    ),
                    DropdownButtonFormField<bool>(
                      key: const ValueKey('pawn-interest-mode'),
                      initialValue: _draft.daily,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Kiểu lãi'),
                      items: const [
                        DropdownMenuItem(
                          value: true,
                          child: Text('Tiền/triệu/ngày'),
                        ),
                        DropdownMenuItem(value: false, child: Text('%/tháng')),
                      ],
                      onChanged: _editable
                          ? (v) => setState(() => _draft.daily = v!)
                          : null,
                    ),
                    TextFormField(
                      key: const ValueKey('pawn-rate'),
                      enabled: _editable,
                      decoration: InputDecoration(
                        labelText: 'Lãi suất',
                        suffixText: _draft.daily ? 'đ/triệu/ngày' : '%/tháng',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      validator: (v) {
                        final rate = num.tryParse(
                          (v ?? '').replaceAll(',', '.'),
                        );
                        return rate == null || !rate.isFinite || rate < 0
                            ? 'Nhập lãi suất không âm'
                            : null;
                      },
                      onChanged: (v) => _draft.rate = v,
                    ),
                    TextFormField(
                      key: ValueKey('pawn-loan-date-${_draft.loanDate}'),
                      readOnly: true,
                      initialValue: DateFormat(
                        'dd/MM/yyyy',
                      ).format(_draft.loanDate),
                      decoration: const InputDecoration(
                        labelText: 'Ngày vay',
                        suffixIcon: Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                        ),
                      ),
                      onTap: _editable ? () => _chooseDate(false) : null,
                    ),
                    TextFormField(
                      key: ValueKey('pawn-due-date-${_draft.dueDate}'),
                      readOnly: true,
                      initialValue: _draft.dueDate == null
                          ? ''
                          : DateFormat('dd/MM/yyyy').format(_draft.dueDate!),
                      decoration: const InputDecoration(
                        labelText: 'Ngày hạn',
                        suffixIcon: Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                        ),
                      ),
                      validator: (_) => _draft.dueDate == null
                          ? 'Vui lòng chọn ngày hạn'
                          : null,
                      onTap: _editable ? () => _chooseDate(true) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('pawn-asset'),
                  enabled: _editable,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Tài sản thế chấp',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Vui lòng nhập tài sản thế chấp'
                      : null,
                  onChanged: (v) => _draft.asset = v,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('pawn-notes'),
                  enabled: _editable,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Ghi chú'),
                  onChanged: (v) => _draft.notes = v,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Đang lưu…' : 'Lưu'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
