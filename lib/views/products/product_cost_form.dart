import '../../core/formatters/money_input_formatter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../widgets/form_section.dart';

class ProductCostForm extends StatefulWidget {
  const ProductCostForm({super.key, required this.onSave, this.note});
  final Future<void> Function(
    DateTime date,
    int amount,
    String notes,
    String requestId,
  )
  onSave;
  final String? note;
  @override
  State<ProductCostForm> createState() => _ProductCostFormState();
}

class _ProductCostFormState extends State<ProductCostForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _notes = TextEditingController();
  DateTime _date = DateTime.now();
  String _requestId = ObjectId().oid;
  bool _saving = false;
  (DateTime, int, String)? _pending;
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
      _pending = (
        _date,
        int.parse(ungroupMoney(_amount.text)),
        _notes.text.trim(),
      );
    }
    setState(() => _saving = true);
    try {
      final value = _pending!;
      await widget.onSave(value.$1, value.$2, value.$3, _requestId);
      if (!mounted) return;
      setState(() {
        _pending = null;
        _requestId = ObjectId().oid;
        _amount.clear();
        _notes.clear();
        _date = DateTime.now();
      });
    } catch (error) {
      if (mounted) {
        final text = '$error'.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              text.isEmpty
                  ? 'Chưa xác nhận lưu chi phí. Bấm Lưu để thử lại.'
                  : text.startsWith('Bad state: ')
                  ? text.substring('Bad state: '.length)
                  : text,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Form(
      key: _form,
      child: FormSection(
        title: null,
        children: [
          if (widget.note != null) ...[
            Text(widget.note!, style: const TextStyle(color: Color(0xFF6E7D83))),
            const SizedBox(height: 16),
          ],
          AbsorbPointer(
            absorbing: _pending != null,
            child: Column(
              children: [
                ResponsiveFormFields(
                  compact: true,
                  fields: [
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
                          labelText: 'Ngày chi phí',
                          suffixIcon: Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                          ),
                        ),
                        child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                      ),
                    ),
                    TextFormField(
                      key: const ValueKey('product-cost-amount'),
                      controller: _amount,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền',
                        suffixText: 'đ',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [const MoneyInputFormatter()],
                      validator: (v) {
                        final n = int.tryParse(ungroupMoney(v ?? ''));
                        return n == null || n < 0 || n > 1000000000000000
                            ? 'Nhập số tiền hợp lệ'
                            : null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('product-cost-notes'),
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
              label: Text(_saving ? 'Đang lưu…' : 'Lưu chi phí'),
            ),
          ),
        ],
      ),
    ),
  );
}
