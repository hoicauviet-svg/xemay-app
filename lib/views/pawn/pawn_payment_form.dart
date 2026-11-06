import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../core/formatters/inventory_formatters.dart';
import '../../core/formatters/money_input_formatter.dart';
import '../../models/pawn/pawn_models.dart';
import '../widgets/form_section.dart';

class PawnPaymentForm extends StatefulWidget {
  const PawnPaymentForm({
    super.key,
    required this.details,
    required this.onPay,
  });
  final PawnDetails details;
  final Future<void> Function(PawnPaymentDraft payment, String requestId) onPay;
  @override
  State<PawnPaymentForm> createState() => _PawnPaymentFormState();
}

class _PawnPaymentFormState extends State<PawnPaymentForm> {
  final _form = GlobalKey<FormState>();
  final _principal = TextEditingController(text: '0'),
      _interest = TextEditingController(text: '0'),
      _collected = TextEditingController(text: '0');
  DateTime _date = DateTime.now();
  DateTime? _appointmentDate;
  bool _appointmentChanged = false;
  bool _appointmentEdited = false;
  bool _saving = false;
  String _requestId = ObjectId().oid;
  PawnPaymentDraft? _pending;
  @override
  void initState() {
    super.initState();
    _fillInterest();
    _fillAppointment();
  }

  @override
  void didUpdateWidget(covariant PawnPaymentForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details != widget.details && _pending == null && !_saving) {
      _fillInterest();
      if (!_appointmentEdited) _fillAppointment();
    }
  }

  void _fillAppointment() {
    _appointmentDate = widget.details.defaultAppointmentAt(DateTime.now());
    final old = widget.details.contract['NgayHan'];
    final next = _appointmentDate;
    _appointmentChanged =
        next != null &&
        (old is! DateTime ||
            next.year != old.year ||
            next.month != old.month ||
            next.day != old.day);
  }

  void _fillInterest() {
    final amount = widget.details.interestAccrualAt(_date)?.roundedAmount;
    _interest.text = amount == null ? '' : groupMoney(amount.toString());
  }

  @override
  void dispose() {
    _principal.dispose();
    _interest.dispose();
    _collected.dispose();
    super.dispose();
  }

  Future<void> _pay({bool settlement = false}) async {
    if (_saving) return;
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      _pending = PawnPaymentDraft(
        pawnId: (widget.details.contract['IdCamDo'] as num).toInt(),
        date: _date,
        appointmentDate: !settlement && _appointmentChanged
            ? _appointmentDate
            : null,
        principal: int.parse(ungroupMoney(_principal.text)),
        interest: int.parse(ungroupMoney(_interest.text)),
        collectedInterest: int.parse(ungroupMoney(_collected.text)),
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
      await widget.onPay(_pending!, _requestId);
      if (mounted) {
        setState(() {
          _pending = null;
          _requestId = ObjectId().oid;
          _principal.text = '0';
          _interest.text = '0';
          _collected.text = '0';
        });
      }
    } on PawnException catch (e) {
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

  Future<void> _settle() async {
    if (_saving || _pending != null || !widget.details.canPay) return;
    final remaining = widget.details.remaining!;
    final interest = int.tryParse(ungroupMoney(_interest.text));
    if (remaining != remaining.round() || interest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chưa xác định được số tiền tất toán. Vui lòng kiểm tra lại phiếu.',
          ),
        ),
      );
      return;
    }
    final principal = remaining.round();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Tất toán cầm đồ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tất toán = Trả toàn bộ tiền gốc + tiền lãi'),
              const SizedBox(height: 16),
              Text('Tiền gốc còn lại: ${money(principal)}'),
              Text('Tiền lãi: ${money(interest)}'),
              const SizedBox(height: 12),
              Text(
                'Tổng tất toán: ${money(principal + interest)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text('Ngày trả: ${DateFormat('dd/MM/yyyy').format(_date)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận tất toán'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _principal.text = groupMoney(principal.toString());
      _collected.text = groupMoney(interest.toString());
    });
    await _pay(settlement: true);
  }

  Widget _moneyField(
    String key,
    String label,
    TextEditingController controller, {
    bool principal = false,
    bool readOnly = false,
  }) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    enabled: _pending == null && !_saving,
    readOnly: readOnly,
    decoration: InputDecoration(labelText: label, suffixText: 'đ'),
    keyboardType: TextInputType.number,
    inputFormatters: [const MoneyInputFormatter()],
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (v) {
      final amount = int.tryParse(ungroupMoney(v ?? ''));
      if (amount == null || amount < 0 || amount > 1000000000000000) {
        return 'Nhập số tiền không âm';
      }
      if (principal && amount > widget.details.remaining!) {
        return 'Tiền gốc vượt số gốc còn lại';
      }
      return null;
    },
  );
  @override
  Widget build(BuildContext context) {
    if (!widget.details.canPay) {
      return Center(
        child: Text(
          widget.details.contract['TrangThai'] == true
              ? 'Phiếu đã chuộc / tất toán.'
              : 'Số gốc còn lại chưa đủ thông tin để thanh toán.',
          textAlign: TextAlign.center,
        ),
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
              'Gốc còn lại: ${money(widget.details.remaining)}',
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
                  key: const ValueKey('pawn-payment-date'),
                  onTap: _pending == null && !_saving
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
                InkWell(
                  key: const ValueKey('pawn-payment-appointment'),
                  onTap: _pending == null && !_saving
                      ? () async {
                          final first = DateTime(
                            _date.year,
                            _date.month,
                            _date.day,
                          );
                          final old = _appointmentDate;
                          final initial =
                              old != null &&
                                  !DateTime(
                                    old.year,
                                    old.month,
                                    old.day,
                                  ).isBefore(first)
                              ? DateTime(old.year, old.month, old.day)
                              : first;
                          final next = await showDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: first,
                            lastDate: DateTime(2079, 6, 6),
                          );
                          if (next != null && mounted) {
                            setState(() {
                              _appointmentDate = next;
                              _appointmentChanged = true;
                              _appointmentEdited = true;
                            });
                          }
                        }
                      : null,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Ngày hẹn tiếp theo',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(
                      _appointmentDate == null
                          ? ''
                          : DateFormat('dd/MM/yyyy').format(_appointmentDate!),
                    ),
                  ),
                ),
                _moneyField(
                  'pawn-payment-principal',
                  'Tiền gốc',
                  _principal,
                  principal: true,
                ),
                _moneyField(
                  'pawn-payment-interest',
                  'Tiền lãi',
                  _interest,
                  readOnly: true,
                ),
                _moneyField(
                  'pawn-payment-collected',
                  'Lãi thực thu',
                  _collected,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('pawn-settle'),
                    onPressed: _saving || _pending != null ? null : _settle,
                    icon: const Icon(Icons.task_alt),
                    label: const Text('Tất toán'),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _pay,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(_saving ? 'Đang lưu…' : 'Thanh toán'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
