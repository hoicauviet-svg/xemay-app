import '../../models/maintenance/record_maintenance.dart';
import '../maintenance/record_actions.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../controllers/funding_details_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../core/formatters/money_input_formatter.dart';
import '../../models/finance/finance_models.dart';
import '../../models/repositories/finance_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_section.dart';
import '../widgets/scrollable_data_table.dart';

class FundingDetailsScreen extends StatefulWidget {
  const FundingDetailsScreen({
    super.key,
    required this.id,
    required this.repository,
  });
  final int id;
  final FinanceRepository repository;
  @override
  State<FundingDetailsScreen> createState() => _FundingDetailsScreenState();
}

class _FundingDetailsScreenState extends State<FundingDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final FundingDetailsController _controller;
  FundingDetails? get _data => _controller.data;
  bool get _loading => _controller.loading;
  String? get _error => _controller.error;
  void _changed() {
    if (mounted) setState(() {});
  }

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
    _controller = FundingDetailsController(widget.repository, widget.id)
      ..addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() => _controller.load();

  String _date(dynamic d) =>
      d is DateTime ? DateFormat('dd/MM/yyyy').format(d) : '';
  String _money(dynamic n) => n == null ? '' : money(n);
  Future<void> _pay(FundingPaymentDraft draft, String id) async {
    await _controller.pay(draft, id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Thanh toán vay vốn thành công')),
      );
    _tabs.animateTo(1);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(title: 'Vay vốn #${widget.id}'),
    body: Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5EAED)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Thông tin'),
              Tab(text: 'Lịch sử'),
              Tab(text: 'Thanh toán'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : _data == null
              ? const SizedBox.shrink()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _information(_data!),
                    _history(_data!),
                    _FundingPaymentForm(details: _data!, onPay: _pay),
                  ],
                ),
        ),
      ],
    ),
  );
  Widget _information(FundingDetails details) {
    if (widget.repository.maintenance != null && _selectedPayment != null) {
      return RecordEditor(
        key: ValueKey('inline:$_selectedPayment:$_deletePayment'),
        repository: widget.repository.maintenance!,
        kind: RecordKind.funding,
        id: widget.id,
        paymentId: _selectedPayment,
        deleting: _selectedPayment != null && _deletePayment,
        embedded: true,
        onSaved: () async {
          _clearPayment();
          await _load();
        },
        onDeleted: () => Navigator.pop(context),
        onCancel: _selectedPayment == null ? null : _clearPayment,
      );
    }

    final r = details.loan;
    final fields = {
      'Mã': '#${r['IdVayVon']}',
      'Đối tác cho vay': '${r['DoiTac'] ?? ''}',
      'Số tiền vay': _money(r['SoTienVay']),
      'Lãi suất': r['LaiSuat'] is num
          ? '${quantity(r['LaiSuat'] as num)} %/tháng'
          : '',
      'Ngày vay': _date(r['NgayVay']),
      'Ngày hẹn': _date(r['NgayHen']),
      'Còn nợ gốc': _money(r['TongConNo']),
      'Ngày tính lãi': _date(r['NgayTinhLai']),
      'Lãi kỳ hiện tại': _money(details.interestAt(DateTime.now())),
      'Ghi chú': '${r['GhiChu'] ?? ''}',
    };
    return SingleChildScrollView(
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
    );
  }

  Widget _history(FundingDetails d) => Padding(
    padding: const EdgeInsets.all(24),
    child: d.payments.isEmpty
        ? const Center(child: Text('Chưa có lịch sử trả nợ.'))
        : ScrollableDataTable(
            fixedHeader: true,
            fitWidth: true,
            columnWidths: const [70, 140, 180, 180, 180, 100],
            columns: const [
              DataColumn(label: Text('MÃ')),
              DataColumn(label: Text('NGÀY TRẢ')),
              DataColumn(label: Text('TRẢ GỐC')),
              DataColumn(label: Text('TRẢ LÃI')),
              DataColumn(label: Text('CÒN NỢ GỐC')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final p in d.payments)
                DataRow(
                  cells: [
                    DataCell(Text('#${p['IdTraNoVayVon']}')),
                    DataCell(Text(_date(p['NgayTra']))),
                    DataCell(Text(_money(p['SoTienTraGoc']))),
                    DataCell(Text(_money(p['SoTienTraLai']))),
                    DataCell(Text(_money(p['ConNoGoc']))),
                    DataCell(
                      RecordActions(
                        repository: widget.repository.maintenance,
                        kind: RecordKind.funding,
                        id: widget.id,
                        paymentId: p['_id'],
                        onSelect: (deleting) =>
                            _choosePayment(p['_id'], deleting),
                        onChanged: _load,
                      ),
                    ),
                  ],
                ),
            ],
          ),
  );
}

class _FundingPaymentForm extends StatefulWidget {
  const _FundingPaymentForm({required this.details, required this.onPay});
  final FundingDetails details;
  final Future<void> Function(FundingPaymentDraft, String) onPay;
  @override
  State<_FundingPaymentForm> createState() => _FundingPaymentFormState();
}

class _FundingPaymentFormState extends State<_FundingPaymentForm> {
  final _form = GlobalKey<FormState>();
  final _principal = TextEditingController(text: '0'),
      _interest = TextEditingController();
  DateTime _date = DateTime.now();
  String _request = ObjectId().oid;
  FundingPaymentDraft? _pending;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _fillInterest();
  }

  void _fillInterest() {
    final amount = widget.details.interestAt(_date);
    _interest.text = amount == null ? '' : groupMoney('$amount');
  }

  @override
  void dispose() {
    _principal.dispose();
    _interest.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (_saving) return;
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      _pending = FundingPaymentDraft(
        loanId: (widget.details.loan['IdVayVon'] as num).toInt(),
        date: _date,
        principal: int.parse(ungroupMoney(_principal.text)),
        interest: int.parse(ungroupMoney(_interest.text)),
      );
      final error = _pending!.validate();
      if (error != null) {
        _pending = null;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.onPay(_pending!, _request);
      if (mounted) {
        setState(() {
          _pending = null;
          _request = ObjectId().oid;
          _principal.text = '0';
          _fillInterest();
        });
      }
    } on FinanceException catch (e) {
      if (mounted) {
        setState(() => _pending = null);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(e.message)));
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

  Widget _money(
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
    validator: (v) {
      final n = int.tryParse(ungroupMoney(v ?? ''));
      if (n == null || n < 0 || n > 1000000000000000) {
        return 'Nhập số tiền không âm';
      }
      if (principal && n > widget.details.remaining!) {
        return 'Tiền trả gốc vượt số còn nợ';
      }
      return null;
    },
  );
  @override
  Widget build(BuildContext context) {
    if (!widget.details.canPay) {
      return const Center(
        child: Text('Khoản vay đã tất toán hoặc chưa xác định được số còn nợ.'),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: FormSection(
          title: null,
          children: [
            Text(
              'Còn nợ gốc: ${money(widget.details.remaining)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF176455),
              ),
            ),
            const SizedBox(height: 24),
            ResponsiveFormFields(
              compact: true,
              fields: [
                InkWell(
                  key: const ValueKey('funding-payment-date'),
                  onTap: !_saving && _pending == null
                      ? () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2079, 6, 6),
                          );
                          if (date != null && mounted) {
                            setState(() {
                              _date = date;
                              _fillInterest();
                            });
                          }
                        }
                      : null,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Ngày trả',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                  ),
                ),
                _money(
                  'funding-payment-principal',
                  'Số tiền trả gốc',
                  _principal,
                  principal: true,
                ),
                _money(
                  'funding-payment-interest',
                  'Số tiền trả lãi',
                  _interest,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _pay,
                icon: const Icon(Icons.payments_outlined),
                label: Text(_saving ? 'Đang lưu…' : 'Thanh toán'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
