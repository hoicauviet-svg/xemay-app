import '../../models/finance/cash_category.dart';
import 'cash_categories_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../core/formatters/inventory_formatters.dart';
import '../../core/formatters/money_input_formatter.dart';
import '../../models/finance/finance_models.dart';
import '../../models/repositories/finance_repository.dart';
import '../widgets/form_popup.dart';
import '../widgets/form_section.dart';

class FinanceEditorPopup extends StatefulWidget {
  const FinanceEditorPopup({
    super.key,
    required this.loans,
    required this.repository,
  });
  final bool loans;
  final FinanceRepository repository;
  @override
  State<FinanceEditorPopup> createState() => _FinanceEditorPopupState();
}

class _FinanceEditorPopupState extends State<FinanceEditorPopup> {
  final _form = GlobalKey<FormState>();
  final _cash = CashEntryDraft();
  final _loan = FundingLoanDraft();
  final _request = ObjectId().oid;
  CashEntryDraft? _pendingCash;
  FundingLoanDraft? _pendingLoan;
  bool _saving = false;
  List<CashCategory> _categories = CashCategory.defaults;
  @override
  void initState() {
    super.initState();
    if (!widget.loans) _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final rows = await widget.repository.categories();
      if (mounted) {
        setState(() {
          _categories = rows;
          if (!rows.any(
            (c) => c.id == _cash.categoryId && c.income == _cash.income,
          )) {
            _cash.categoryId = null;
            _cash.categoryName = null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Chưa tải được danh mục.');
    }
  }

  Widget _categoryField() => Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          key: ValueKey('cash-category-${_cash.income}-${_cash.categoryId}'),
          initialValue:
              _categories.any(
                (c) => c.id == _cash.categoryId && c.income == _cash.income,
              )
              ? _cash.categoryId
              : null,
          decoration: const InputDecoration(labelText: 'Danh mục'),
          isExpanded: true,
          items: [
            for (final c in _categories.where((c) => c.income == _cash.income))
              DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: !_editable
              ? null
              : (id) => setState(() {
                  final c = _categories.firstWhere((c) => c.id == id);
                  _cash.categoryId = c.id;
                  _cash.categoryName = c.name;
                }),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        height: 48,
        width: 48,
        child: IconButton.outlined(
          tooltip: 'Quản lý danh mục',
          icon: const Icon(Icons.settings_outlined),
          onPressed: !_editable
              ? null
              : () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => CashCategoriesPopup(
                      repository: widget.repository,
                      initialIncome: _cash.income,
                    ),
                  );
                  await _loadCategories();
                },
        ),
      ),
    ],
  );

  String? _error;
  bool get _editable =>
      !_saving && _pendingCash == null && _pendingLoan == null;
  Future<void> _save() async {
    if (_saving) return;
    if (_pendingCash == null && _pendingLoan == null) {
      if (!_form.currentState!.validate()) return;
      final error = widget.loans ? _loan.validate() : _cash.validate();
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      if (widget.loans) {
        _pendingLoan = _loan.snapshot();
      } else {
        _pendingCash = _cash.snapshot();
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.loans
          ? await widget.repository.createLoan(
              _pendingLoan!,
              requestId: _request,
            )
          : await widget.repository.createCash(
              _pendingCash!,
              requestId: _request,
            );
      if (mounted) Navigator.pop(context, id);
    } on FinanceException catch (e) {
      if (mounted) {
        setState(() {
          _pendingCash = null;
          _pendingLoan = null;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa xác nhận lưu. Bấm Lưu để thử lại phiếu này.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _date(
    String label,
    DateTime? value,
    void Function(DateTime) changed,
  ) => InkWell(
    onTap: _editable
        ? () async {
            final date = await showDatePicker(
              context: context,
              initialDate: value ?? _loan.date,
              firstDate: DateTime(1900),
              lastDate: DateTime(2079, 6, 6),
            );
            if (date != null && mounted) setState(() => changed(date));
          }
        : null,
    child: InputDecorator(
      key: ValueKey('finance-date-$label'),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
      ),
      child: Text(value == null ? '' : DateFormat('dd/MM/yyyy').format(value)),
    ),
  );
  Widget _amount(
    String key,
    String label,
    String value,
    void Function(String) changed,
  ) => TextFormField(
    key: ValueKey(key),
    enabled: _editable,
    initialValue: groupMoney(value),
    decoration: InputDecoration(labelText: label, suffixText: 'đ'),
    keyboardType: TextInputType.number,
    inputFormatters: [const MoneyInputFormatter()],
    validator: (v) => (int.tryParse(ungroupMoney(v ?? '')) ?? 0) <= 0
        ? 'Nhập số tiền lớn hơn 0'
        : null,
    onChanged: (v) => setState(() => changed(ungroupMoney(v))),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: FormPopup(
      title: widget.loans ? 'Thêm khoản vay vốn' : 'Thêm khoản thu/chi',
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
                  fields: widget.loans
                      ? [
                          _amount(
                            'funding-amount',
                            'Số tiền vay',
                            _loan.amount,
                            (v) => _loan.amount = v,
                          ),
                          _date('Ngày vay', _loan.date, (d) => _loan.date = d),
                          TextFormField(
                            key: const ValueKey('funding-partner'),
                            enabled: _editable,
                            decoration: const InputDecoration(
                              labelText: 'Đối tác cho vay',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Vui lòng nhập đối tác'
                                : null,
                            onChanged: (v) => _loan.partner = v,
                          ),
                          TextFormField(
                            key: const ValueKey('funding-rate'),
                            enabled: _editable,
                            decoration: const InputDecoration(
                              labelText: 'Lãi suất',
                              suffixText: '%/tháng',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            validator: (v) {
                              final rate = num.tryParse(
                                (v ?? '').replaceAll(',', '.'),
                              );
                              return rate == null || !rate.isFinite || rate < 0
                                  ? 'Nhập lãi suất không âm'
                                  : null;
                            },
                            onChanged: (v) => _loan.rate = v,
                          ),
                          _date(
                            'Ngày hẹn',
                            _loan.dueDate,
                            (d) => _loan.dueDate = d,
                          ),
                          _date(
                            'Ngày tính lãi',
                            _loan.interestDate ?? _loan.date,
                            (d) => _loan.interestDate = d,
                          ),
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Còn nợ gốc',
                            ),
                            child: Text(
                              financeMoney(_loan.amount) == null
                                  ? ''
                                  : money(financeMoney(_loan.amount)),
                            ),
                          ),
                        ]
                      : [
                          _date(
                            'Ngày tháng',
                            _cash.date,
                            (d) => _cash.date = d,
                          ),
                          DropdownButtonFormField<bool>(
                            key: const ValueKey('cash-type'),
                            initialValue: _cash.income,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Loại thu/chi',
                            ),
                            items: const [
                              DropdownMenuItem(value: true, child: Text('Thu')),
                              DropdownMenuItem(
                                value: false,
                                child: Text('Chi'),
                              ),
                            ],
                            onChanged: _editable
                                ? (v) => setState(() {
                                    _cash.income = v!;
                                    _cash.categoryId = null;
                                    _cash.categoryName = null;
                                  })
                                : null,
                          ),
                          _categoryField(),
                          _amount(
                            'cash-amount',
                            'Số tiền',
                            _cash.amount,
                            (v) => _cash.amount = v,
                          ),
                        ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: ValueKey(widget.loans ? 'funding-notes' : 'cash-reason'),
                  enabled: _editable,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: widget.loans ? 'Ghi chú' : 'Lý do',
                  ),
                  validator: (v) =>
                      !widget.loans && (v == null || v.trim().isEmpty)
                      ? 'Vui lòng nhập lý do'
                      : null,
                  onChanged: (v) {
                    if (widget.loans) {
                      _loan.notes = v;
                    } else {
                      _cash.reason = v;
                    }
                  },
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
