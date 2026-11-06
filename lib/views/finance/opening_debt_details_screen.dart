import '../../models/maintenance/record_maintenance.dart';
import '../maintenance/record_actions.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../controllers/opening_debt_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../core/formatters/money_input_formatter.dart';
import '../../models/finance/finance_models.dart';
import '../../models/finance/opening_debt.dart';
import '../../models/repositories/opening_debt_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_section.dart';
import '../widgets/scrollable_data_table.dart';

class OpeningDebtDetailsScreen extends StatefulWidget {
  const OpeningDebtDetailsScreen({
    super.key,
    required this.id,
    required this.repository,
  });
  final int id;
  final OpeningDebtRepository repository;
  @override
  State<OpeningDebtDetailsScreen> createState() =>
      _OpeningDebtDetailsScreenState();
}

class _OpeningDebtDetailsScreenState extends State<OpeningDebtDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final OpeningDebtDetailsController _controller;
  late final TabController _tabs;
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
    _tabs = TabController(length: 3, vsync: this);
    _controller = OpeningDebtDetailsController(widget.repository, widget.id);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _date(dynamic v) =>
      v is DateTime ? DateFormat('dd/MM/yyyy').format(v) : '';
  String _money(dynamic v) => v == null ? '' : money(v);
  Future<void> _pay(OpeningDebtPayment payment, String request) async {
    await _controller.pay(payment, request);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Trả nợ thành công')));
    _tabs.animateTo(1);
    await _controller.load();
  }

  Widget _openingInformation(Widget original) {
    if (widget.repository.maintenance != null && _selectedPayment != null) {
      return RecordEditor(
        key: ValueKey('inline:$_selectedPayment:$_deletePayment'),
        repository: widget.repository.maintenance!,
        kind: RecordKind.openingDebt,
        id: widget.id,
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
    return original;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(title: 'Nợ cũ #${widget.id}'),
    body: Column(
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Thông tin'),
            Tab(text: 'Lịch sử trả nợ'),
            Tab(text: 'Trả nợ'),
          ],
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (_controller.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_controller.error != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_controller.error!),
                      TextButton(
                        onPressed: _controller.load,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                );
              }
              final data = _controller.data;
              if (data == null) return const SizedBox.shrink();
              final fields = <String, String>{
                'Khách hàng': '${data.customer?['TenKhachHang'] ?? ''}',
                'Số điện thoại': '${data.customer?['SoDienThoai'] ?? ''}',
                'Địa chỉ': '${data.customer?['DiaChiChiTiet'] ?? ''}',
                'Tổng nợ': _money(data.debt['TongNo']),
                'Đã trả': _money(data.debt['SoTienDaTra']),
                'Còn nợ': _money(data.remaining),
                'Ngày hẹn': _date(data.debt['NgayHen']),
                'Ngày tính lãi': _date(data.debt['NgayTinhLai']),
                'Ghi chú': '${data.debt['GhiChu'] ?? ''}',
              };
              return TabBarView(
                controller: _tabs,
                children: [
                  _openingInformation(
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: FormSection(
                        title: null,
                        children: [
                          ResponsiveFormFields(
                            compact: true,
                            fields: [
                              for (final f in fields.entries)
                                InputDecorator(
                                  decoration: InputDecoration(labelText: f.key),
                                  child: SelectableText(f.value),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  data.payments.isEmpty
                      ? const Center(child: Text('Chưa có lịch sử trả nợ.'))
                      : Padding(
                          padding: const EdgeInsets.all(20),
                          child: ScrollableDataTable(
                            fixedHeader: true,
                            fitWidth: true,
                            columnWidths: const [
                              60,
                              120,
                              140,
                              140,
                              140,
                              140,
                              100,
                            ],
                            columns: const [
                              DataColumn(label: Text('Mã')),
                              DataColumn(label: Text('Ngày trả')),
                              DataColumn(label: Text('Tiền trả nợ')),
                              DataColumn(label: Text('Tiền lãi')),
                              DataColumn(label: Text('Lãi thực thu')),
                              DataColumn(label: Text('Còn nợ')),
                              DataColumn(label: Text('')),
                            ],
                            rows: [
                              for (final row in data.payments)
                                DataRow(
                                  cells: [
                                    DataCell(Text('${row['Id'] ?? ''}')),
                                    DataCell(Text(_date(row['NgayTra']))),
                                    DataCell(Text(_money(row['SoTienTra']))),
                                    DataCell(Text(_money(row['TienLai']))),
                                    DataCell(Text(_money(row['LaiThu']))),
                                    DataCell(Text(_money(row['ConNo']))),
                                    DataCell(
                                      RecordActions(
                                        repository:
                                            widget.repository.maintenance,
                                        kind: RecordKind.openingDebt,
                                        id: widget.id,
                                        paymentId: row['_id'],
                                        onSelect: (deleting) => _choosePayment(
                                          row['_id'],
                                          deleting,
                                        ),
                                        onChanged: _controller.load,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                  _DebtPaymentForm(data: data, onPay: _pay),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _DebtPaymentForm extends StatefulWidget {
  const _DebtPaymentForm({required this.data, required this.onPay});
  final OpeningDebtDetails data;
  final Future<void> Function(OpeningDebtPayment, String) onPay;
  @override
  State<_DebtPaymentForm> createState() => _DebtPaymentFormState();
}

class _DebtPaymentFormState extends State<_DebtPaymentForm> {
  final _form = GlobalKey<FormState>();
  final _principal = TextEditingController(text: '0'),
      _interest = TextEditingController(text: '0'),
      _collected = TextEditingController(text: '0');
  DateTime _date = DateTime.now();
  String _request = ObjectId().oid;
  OpeningDebtPayment? _pending;
  bool _saving = false;
  @override
  void dispose() {
    _principal.dispose();
    _interest.dispose();
    _collected.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      final draft = OpeningDebtPayment(
        debtId: (widget.data.debt['Id'] as num).toInt(),
        date: _date,
        principal: int.parse(ungroupMoney(_principal.text)),
        interest: int.parse(ungroupMoney(_interest.text)),
        collectedInterest: int.parse(ungroupMoney(_collected.text)),
      );
      final error = draft.validate();
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
      _pending = draft;
    }
    setState(() => _saving = true);
    try {
      await widget.onPay(_pending!, _request);
      if (mounted) {
        setState(() {
          _pending = null;
          _request = ObjectId().oid;
          _principal.text = '0';
          _interest.text = '0';
          _collected.text = '0';
        });
      }
    } on FinanceException catch (e) {
      if (mounted) {
        setState(() => _pending = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa xác nhận lưu. Bấm Trả nợ để thử lại lần này.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _amount(
    String key,
    String label,
    TextEditingController controller, {
    bool principal = false,
  }) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    enabled: !_saving && _pending == null,
    decoration: InputDecoration(labelText: label, suffixText: 'đ'),
    keyboardType: TextInputType.number,
    inputFormatters: [const MoneyInputFormatter()],
    onChanged: (_) => setState(() {}),
    validator: (v) {
      final n = int.tryParse(ungroupMoney(v ?? ''));
      if (n == null || n < 0 || n > 1000000000000000) {
        return 'Nhập số tiền không âm';
      }
      if (principal && n > widget.data.remaining!) {
        return 'Tiền trả nợ vượt số còn nợ';
      }
      return null;
    },
  );
  @override
  Widget build(BuildContext context) {
    final due = widget.data.remaining;
    if (due == null || !due.isFinite || due <= 0) {
      return const Center(
        child: Text('Khoản nợ đã trả hết hoặc chưa xác định được số còn nợ.'),
      );
    }
    final amount = int.tryParse(ungroupMoney(_principal.text)) ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: FormSection(
          title: null,
          children: [
            Text(
              'Tổng nợ: ${money(due)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            ResponsiveFormFields(
              compact: true,
              fields: [
                InkWell(
                  key: const ValueKey('opening-payment-date'),
                  onTap: _saving || _pending != null
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2079, 6, 6),
                          );
                          if (d != null && mounted) setState(() => _date = d);
                        },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Ngày trả',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                  ),
                ),
                _amount(
                  'opening-payment-principal',
                  'Tiền trả nợ',
                  _principal,
                  principal: true,
                ),
                _amount('opening-payment-interest', 'Tiền lãi', _interest),
                _amount(
                  'opening-payment-collected',
                  'Lãi thực thu',
                  _collected,
                ),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Còn nợ'),
                  child: Text(money(due - amount)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.payments_outlined),
                label: Text(_saving ? 'Đang lưu…' : 'Trả nợ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
