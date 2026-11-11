import 'package:flutter/material.dart';
import '../../models/customers/customer_models.dart';
import '../widgets/editor_shell.dart';
import '../widgets/form_section.dart';

class CustomerEditorPopup extends StatefulWidget {
  const CustomerEditorPopup({
    super.key,
    required this.onCreate,
    this.initial,
    this.embedded = false,
    this.onSaved,
    this.onDelete,
  });
  final Map<String, dynamic>? initial;
  final Future<Map<String, dynamic>> Function(CustomerDraft) onCreate;
  final bool embedded;
  final Future<void> Function()? onSaved;
  final Future<void> Function()? onDelete;
  @override
  State<CustomerEditorPopup> createState() => _CustomerEditorPopupState();
}

class _CustomerEditorPopupState extends State<CustomerEditorPopup> {
  final _form = GlobalKey<FormState>();
  final _draft = CustomerDraft();
  @override
  void initState() {
    super.initState();
    final row = widget.initial;
    if (row != null) {
      _draft.name = '${row['TenKhachHang'] ?? ''}';
      _draft.phone = '${row['SoDienThoai'] ?? ''}';
      _draft.cccd = '${row['SoCCCD'] ?? ''}';
      _draft.cmnd = '${row['SoCMND'] ?? ''}';
      _draft.issueDate = CustomerDraft.formatIssueDate(row['NgayCap']);
      _draft.issuePlace = '${row['NoiCap'] ?? ''}';
      _draft.address = '${row['DiaChiHienThi'] ?? row['DiaChiChiTiet'] ?? ''}';
    }
  }

  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final customer = await widget.onCreate(_draft);
      if (mounted) {
        if (widget.embedded) {
          setState(() => _saving = false);
          await widget.onSaved?.call();
        } else {
          Navigator.pop(context, customer);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is CustomerException
              ? e.message
              : 'Không lưu được khách hàng. Vui lòng thử lại.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: EditorShell(
      embedded: widget.embedded,
      title: widget.initial == null
          ? 'Thêm khách hàng mới'
          : 'Cập nhật khách hàng',
      canClose: !_saving,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Form(
          key: _form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                FormSection(
                  title: 'Thông tin khách hàng',
                  children: [
                    ResponsiveFormFields(
                      fields: [
                        TextFormField(
                          key: const ValueKey('customer-name'),
                          initialValue: _draft.name,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Tên khách hàng *',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Vui lòng nhập tên khách hàng'
                              : null,
                          onChanged: (v) => _draft.name = v,
                        ),
                        TextFormField(
                          key: const ValueKey('customer-phone'),
                          initialValue: _draft.phone,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Số điện thoại',
                          ),
                          keyboardType: TextInputType.phone,
                          onChanged: (v) => _draft.phone = v,
                        ),
                        TextFormField(
                          key: const ValueKey('customer-cccd'),
                          initialValue: _draft.cccd,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Số CCCD',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _draft.cccd = v,
                        ),
                        TextFormField(
                          key: const ValueKey('customer-cmnd'),
                          initialValue: _draft.cmnd,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Số CMND',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _draft.cmnd = v,
                        ),
                        TextFormField(
                          key: const ValueKey('customer-issue-date'),
                          initialValue: _draft.issueDate,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Ngày cấp',
                            hintText: 'dd/MM/yyyy',
                          ),
                          validator: _draft.validateIssueDate,
                          onChanged: (v) => _draft.issueDate = v,
                        ),
                        TextFormField(
                          key: const ValueKey('customer-issue-place'),
                          initialValue: _draft.issuePlace,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Nơi cấp',
                          ),
                          onChanged: (v) => _draft.issuePlace = v,
                        ),
                        TextFormField(
                          key: const ValueKey('customer-address'),
                          initialValue: _draft.address,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Địa chỉ chi tiết',
                            hintText: 'Nhập thôn, số nhà, xã…',
                          ),
                          onChanged: (v) => _draft.address = v,
                        ),
                      ],
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Material(
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onDelete != null)
                    TextButton.icon(
                      onPressed: _saving ? null : widget.onDelete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Xóa khách hàng'),
                    ),
                  const Spacer(),
                  if (!widget.embedded)
                    OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Hủy'),
                    ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Lưu khách hàng'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
