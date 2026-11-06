import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../core/formatters/inventory_formatters.dart';
import '../../core/formatters/money_input_formatter.dart';
import '../../models/orders/order_details.dart';
import '../widgets/form_section.dart';

class OrderPaymentForm extends StatefulWidget {
  const OrderPaymentForm({
    super.key,
    required this.order,
    required this.onSave,
  });
  final OrderDetails order;
  final Future<void> Function(
    DateTime date,
    int amount,
    String notes,
    String requestId,
    DateTime? nextAppointment,
  )
  onSave;
  @override
  State<OrderPaymentForm> createState() => _OrderPaymentFormState();
}

class _OrderPaymentFormState extends State<OrderPaymentForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _notes = TextEditingController();
  DateTime _date = DateTime.now();
  String _requestId = ObjectId().oid;
  (DateTime, int, String, DateTime?)? _pending;
  DateTime? _appointment;
  @override
  void initState() {
    super.initState();
    _appointment = widget.order.nextAppointmentAt(DateTime.now());
  }

  bool _saving = false;
  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      if (_appointment != null &&
          OrderDetails.day(_appointment!).isBefore(OrderDetails.day(_date))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ngày hẹn tiếp theo không được trước ngày thanh toán.',
            ),
          ),
        );
        return;
      }
      _pending = (
        _date,
        int.tryParse(ungroupMoney(_amount.text)) ?? 0,
        _notes.text.trim(),
        _appointment,
      );
    }
    setState(() => _saving = true);
    try {
      final pending = _pending!;
      await widget.onSave(
        pending.$1,
        pending.$2,
        pending.$3,
        _requestId,
        pending.$4,
      );
      if (mounted) {
        setState(() {
          _pending = null;
          _requestId = ObjectId().oid;
          _amount.clear();
          _notes.clear();
        });
      }
    } on OrderException catch (e) {
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
            content: Text(
              'Chưa xác nhận thanh toán. Bấm Lưu để thử lại lần thanh toán này.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.order.canPay) {
      return Center(
        child: Text(
          widget.order.due == 0
              ? 'Đơn hàng đã thanh toán đủ.'
              : 'Công nợ chưa đủ thông tin hoặc có nhiều sổ nợ. Cần đối soát trước khi thanh toán.',
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
            AbsorbPointer(
              absorbing: _pending != null,
              child: Column(
                children: [
                  ResponsiveFormFields(
                    compact: true,
                    fields: [
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Đã thanh toán',
                        ),
                        child: Text(money(widget.order.paid)),
                      ),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Còn nợ'),
                        child: Text(money(widget.order.due)),
                      ),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100, 12, 31),
                          );
                          if (date != null && mounted) {
                            setState(() => _date = date);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Ngày thanh toán',
                            suffixIcon: Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                            ),
                          ),
                          child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                        ),
                      ),
                      TextFormField(
                        key: const ValueKey('order-payment-amount'),
                        controller: _amount,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Số tiền trả gốc',
                          suffixText: 'đ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [const MoneyInputFormatter()],
                        validator: (v) {
                          final amount = int.tryParse(ungroupMoney(v ?? ''));
                          if ((amount == null && v!.trim().isNotEmpty) ||
                              (amount ?? 0) < 0 ||
                              (amount ?? 0) > 1000000000000000) {
                            return 'Số tiền không hợp lệ';
                          }
                          if ((amount ?? 0) == 0 &&
                              widget.order.interestAt(_date) == 0) {
                            return 'Nhập số tiền trả gốc';
                          }
                          if ((amount ?? 0) > widget.order.due!) {
                            return 'Số tiền vượt số còn nợ';
                          }
                          return null;
                        },
                      ),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Ngày tính lãi',
                        ),
                        child: Text(
                          widget.order.interestStart == null
                              ? ''
                              : DateFormat(
                                  'dd/MM/yyyy',
                                ).format(widget.order.interestStart!),
                        ),
                      ),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _appointment ?? _date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100, 12, 31),
                          );
                          if (picked != null && mounted) {
                            setState(() => _appointment = picked);
                          }
                        },
                        child: InputDecorator(
                          key: const ValueKey('order-next-appointment'),
                          decoration: const InputDecoration(
                            labelText: 'Ngày hẹn tiếp theo',
                            suffixIcon: Icon(Icons.event_outlined, size: 18),
                          ),
                          child: Text(
                            _appointment == null
                                ? ''
                                : DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(_appointment!),
                          ),
                        ),
                      ),
                      InputDecorator(
                        key: const ValueKey('order-payment-interest'),
                        decoration: const InputDecoration(
                          labelText: 'Tiền lãi (2%/tháng)',
                        ),
                        child: Text(money(widget.order.interestAt(_date))),
                      ),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tổng tiền thu',
                        ),
                        child: Text(
                          money(
                            (int.tryParse(ungroupMoney(_amount.text)) ?? 0) +
                                widget.order.interestAt(_date),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const ValueKey('order-payment-notes'),
                    controller: _notes,
                    maxLines: 3,
                    maxLength: 10000,
                    decoration: const InputDecoration(labelText: 'Ghi chú'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Đang lưu…' : 'Lưu thanh toán'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
