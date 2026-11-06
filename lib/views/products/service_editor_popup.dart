import 'package:flutter/material.dart';
import '../../controllers/service_controller.dart';
import '../../models/services/service_models.dart';
import '../widgets/editor_shell.dart';
import '../widgets/form_section.dart';

class ServiceEditorPopup extends StatefulWidget {
  const ServiceEditorPopup({
    super.key,
    this.embedded = false,
    this.onSaved,
    this.onDelete,
    required this.controller,
    this.existing,
  });
  final ServiceController controller;
  final ServiceItem? existing;
  final bool embedded;
  final Future<void> Function()? onSaved;
  final Future<void> Function()? onDelete;
  @override
  State<ServiceEditorPopup> createState() => _ServiceEditorPopupState();
}

class _ServiceEditorPopupState extends State<ServiceEditorPopup> {
  final _form = GlobalKey<FormState>();
  final _draft = ServiceDraft();
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _draft.name = e.name;
      _draft.description = e.description;
      _draft.price = '${e.price}';
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
      final item = widget.existing == null
          ? await widget.controller.create(_draft)
          : await widget.controller.repository.update(
              widget.existing!.id,
              _draft,
            );
      if (mounted) {
        if (widget.embedded) {
          setState(() => _saving = false);
          await widget.onSaved?.call();
        } else {
          Navigator.pop(context, item);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ServiceException
              ? e.message
              : 'Không lưu được dịch vụ. Vui lòng thử lại.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: EditorShell(
      embedded: widget.embedded,
      title: widget.existing == null ? 'Thêm dịch vụ' : 'Cập nhật dịch vụ',
      canClose: !_saving,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Form(
          key: _form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FormSection(
              title: 'Thông tin dịch vụ',
              children: [
                ResponsiveFormFields(
                  fields: [
                    TextFormField(
                      key: const ValueKey('service-name'),
                      initialValue: _draft.name,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Tên dịch vụ *',
                      ),
                      onChanged: (v) => _draft.name = v,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Vui lòng nhập tên dịch vụ'
                          : null,
                    ),
                    TextFormField(
                      key: const ValueKey('service-price'),
                      initialValue: _draft.price,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Giá tiền *',
                        suffixText: 'đ',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _draft.price = v,
                      validator: (_) => _draft.priceError,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('service-description'),
                  initialValue: _draft.description,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Mô tả'),
                  maxLines: 4,
                  onChanged: (v) => _draft.description = v,
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
                    label: const Text('Lưu dịch vụ'),
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
