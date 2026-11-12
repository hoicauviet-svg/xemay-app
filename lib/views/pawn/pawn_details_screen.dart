import '../../models/maintenance/record_maintenance.dart';
import '../maintenance/record_actions.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/pawn_details_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/pawn/pawn_models.dart';
import '../../models/repositories/pawn_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_section.dart';
import '../widgets/scrollable_data_table.dart';
import 'pawn_payment_form.dart';
import '../printing/pawn_contract_screen.dart';

class PawnDetailsScreen extends StatefulWidget {
  const PawnDetailsScreen({
    super.key,
    required this.id,
    required this.repository,
  });
  final int id;
  final PawnRepository repository;
  @override
  State<PawnDetailsScreen> createState() => _PawnDetailsScreenState();
}

class _PawnDetailsScreenState extends State<PawnDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final PawnDetailsController _controller;
  late final TabController _tabs;
  Timer? _dayTimer;
  void _scheduleDayRefresh() {
    final now = DateTime.now();
    _dayTimer = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleDayRefresh();
      },
    );
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
    _controller = PawnDetailsController(widget.repository, widget.id);
    unawaited(_controller.load());
    _scheduleDayRefresh();
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    _tabs.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _value(dynamic v) => v == null ? '' : '$v';
  String _money(dynamic v) => v == null ? '' : money(v);
  String _date(dynamic v) =>
      v is DateTime ? DateFormat('dd/MM/yyyy').format(v) : '';
  Future<void> _pay(PawnPaymentDraft payment, String requestId) async {
    await widget.repository.pay(payment, requestId: requestId);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Thanh toán thành công')));
    _tabs.animateTo(1);
    await _controller.load();
  }

  Future<void> _editContract(bool deleting) async {
    final maintenance = widget.repository.maintenance;
    if (maintenance == null) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecordEditor(
        repository: maintenance,
        kind: RecordKind.pawn,
        id: widget.id,
        deleting: deleting,
      ),
    );
    if (changed != true || !mounted) return;
    if (deleting) {
      Navigator.pop(context);
    } else {
      await _controller.load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(title: 'Cầm đồ #${widget.id}'),
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
            labelColor: const Color(0xFF176455),
            indicatorColor: const Color(0xFF176455),
            tabs: const [
              Tab(text: 'Thông tin'),
              Tab(text: 'Lịch sử'),
              Tab(text: 'Thanh toán'),
            ],
          ),
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
              final details = _controller.data;
              if (details == null) return const SizedBox.shrink();
              return TabBarView(
                controller: _tabs,
                children: [
                  _information(details),
                  _history(details),
                  PawnPaymentForm(details: details, onPay: _pay),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
  Widget _information(PawnDetails details) {
    if (widget.repository.maintenance != null && _selectedPayment != null) {
      return RecordEditor(
        key: ValueKey('inline:$_selectedPayment:$_deletePayment'),
        repository: widget.repository.maintenance!,
        kind: RecordKind.pawn,
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

    final r = details.contract, c = details.customer;
    final today = DateTime.now();
    final overdue = details.overdueDaysAt(today);
    final interest = details.interestAccrualAt(today);
    final fields = <String, String>{
      'Mã': '#${r['IdCamDo']}',
      'Khách hàng': _value(c?['TenKhachHang'] ?? r['TenKhachHang']),
      'Số điện thoại': _value(c?['SoDienThoai'] ?? r['SoDienThoai']),
      'Tài sản thế chấp': _value(r['TaiSanTheChap']),
      'Số tiền vay': _money(r['SoTienVay']),
      'Kiểu lãi': r['NgayPhanTram'] == true
          ? 'Tiền/triệu/ngày'
          : r['NgayPhanTram'] == false
          ? '%/tháng'
          : '',
      'Lãi suất': r['LaiSuat'] is num
          ? '${quantity(r['LaiSuat'] as num)} ${r['NgayPhanTram'] == true
                ? 'đ/triệu/ngày'
                : r['NgayPhanTram'] == false
                ? '%/tháng'
                : ''}'
          : '',
      'Ngày vay': _date(r['NgayVay']),
      'Ngày hạn': _date(r['NgayHan']),
      'Số ngày quá hạn': overdue == null ? '' : '$overdue ngày',
      'Ngày tính lãi': _date(details.interestStartDate),
      'Số ngày tính lãi': interest == null ? '' : '${interest.days} ngày',
      'Lãi kỳ hiện tại': _money(interest?.roundedAmount),
      'Gốc đã thu': _money(details.principalPaid),
      'Gốc còn lại': _money(details.remaining),
      'Trạng thái': r['TrangThai'] == true
          ? 'Đã chuộc / tất toán'
          : r['TrangThai'] == false
          ? 'Đang cầm'
          : '',
      'Ghi chú': _value(r['GhiChu']),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => PawnContractScreen(details: details),
                  ),
                ),
                icon: const Icon(Icons.print_outlined),
                label: const Text('In hợp đồng'),
              ),
              if (widget.repository.maintenance != null) ...[
                OutlinedButton.icon(
                  onPressed: () => _editContract(false),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Cập nhật thông tin'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editContract(true),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFB44141),
                  ),
                  label: const Text('Xóa phiếu'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          if (overdue != null && overdue > 0)
            Semantics(
              liveRegion: true,
              child: Container(
                key: const ValueKey('pawn-overdue-notice'),
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  border: Border.all(color: const Color(0xFFFFB74D)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFB85C00),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Phiếu cầm đồ đã quá hạn $overdue ngày',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9A4F00),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          FormSection(
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
        ],
      ),
    );
  }

  Widget _history(PawnDetails details) => Padding(
    padding: const EdgeInsets.all(24),
    child: details.payments.isEmpty
        ? const Center(child: Text('Chưa có lịch sử thanh toán.'))
        : ScrollableDataTable(
            fixedHeader: true,
            fitWidth: true,
            columnWidths: const [80, 140, 160, 160, 160, 100],
            columns: const [
              DataColumn(label: Text('MÃ')),
              DataColumn(label: Text('NGÀY TRẢ')),
              DataColumn(label: Text('TIỀN GỐC')),
              DataColumn(label: Text('TIỀN LÃI')),
              DataColumn(label: Text('LÃI THỰC THU')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final p in details.payments)
                DataRow(
                  cells: [
                    DataCell(Text('#${p['IdTraNoCamDo']}')),
                    DataCell(Text(_date(p['NgayTra']))),
                    DataCell(Text(_money(p['TienGoc']))),
                    // Legacy pawn payment rows store these two amounts in the
                    // opposite fields from the labels used in the history view.
                    DataCell(Text(_money(p['LaiThu']))),
                    DataCell(Text(_money(p['SoTienLai']))),
                    DataCell(
                      RecordActions(
                        repository: widget.repository.maintenance,
                        kind: RecordKind.pawn,
                        id: widget.id,
                        paymentId: p['_id'],
                        onSelect: (deleting) =>
                            _choosePayment(p['_id'], deleting),
                        onChanged: _controller.load,
                      ),
                    ),
                  ],
                ),
            ],
          ),
  );
}
