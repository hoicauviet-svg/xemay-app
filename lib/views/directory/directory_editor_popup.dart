import 'package:flutter/material.dart';
import '../../controllers/directory_controller.dart';
import '../../models/directory/directory_models.dart';
import '../widgets/editor_shell.dart';
import '../widgets/form_section.dart';

class DirectoryEditorPopup extends StatefulWidget {
  const DirectoryEditorPopup({
    super.key,
    this.embedded = false,
    this.onSaved,
    this.onDelete,
    required this.directory,
    required this.kind,
    this.initialName = '',
    this.existing,
  });
  final DirectoryController directory;
  final DirectoryKind kind;
  final String initialName;
  final DirectoryEntry? existing;
  final bool embedded;
  final Future<void> Function()? onSaved;
  final Future<void> Function()? onDelete;
  @override
  State<DirectoryEditorPopup> createState() => _DirectoryEditorPopupState();
}

class _DirectoryEditorPopupState extends State<DirectoryEditorPopup> {
  late final DirectoryEditController _controller;
  final _formKey = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    _controller = DirectoryEditController(
      widget.directory,
      widget.kind,
      widget.initialName,
      existing: widget.existing,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final entry = await _controller.save();
    if (entry != null && mounted) {
      if (widget.embedded) {
        await widget.onSaved?.call();
      } else {
        Navigator.pop(context, entry);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final draft = _controller.draft;
      return PopScope(
        canPop: !_controller.saving,
        child: EditorShell(
          embedded: widget.embedded,
          title:
              '${widget.existing == null ? 'Thêm' : 'Cập nhật'} ${widget.kind == DirectoryKind.partner ? 'đối tác / nhà cung cấp' : 'vận chuyển'}',
          canClose: !_controller.saving,
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    FormSection(
                      title: widget.kind == DirectoryKind.partner
                          ? 'Thông tin đối tác / nhà cung cấp'
                          : 'Thông tin vận chuyển',
                      children: [
                        ResponsiveFormFields(
                          fields: [
                            TextFormField(
                              key: const ValueKey('directory-name'),
                              initialValue: draft.name,
                              enabled: !_controller.saving,
                              decoration: const InputDecoration(
                                labelText: 'Tên',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Vui lòng nhập tên'
                                  : null,
                              onChanged: (v) => draft.name = v,
                            ),
                            _field(
                              'directory-phone',
                              'Số điện thoại',
                              (v) => draft.phone = v,
                              keyboard: TextInputType.phone,
                            ),
                            if (widget.kind == DirectoryKind.partner) ...[
                              _field(
                                'directory-tax',
                                'Mã số thuế',
                                (v) => draft.taxCode = v,
                              ),
                              _field(
                                'directory-representative',
                                'Người đại diện',
                                (v) => draft.representative = v,
                              ),
                            ] else
                              _field(
                                'directory-plate',
                                'Biển số xe',
                                (v) => draft.plate = v,
                              ),
                          ],
                        ),
                        if (widget.kind == DirectoryKind.partner) ...[
                          const SizedBox(height: 20),
                          _field(
                            'directory-address',
                            'Địa chỉ',
                            (v) => draft.address = v,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    FormSection(
                      title: 'Ghi chú',
                      children: [
                        TextFormField(
                          key: const ValueKey('directory-notes'),
                          initialValue: draft.notes,
                          enabled: !_controller.saving,
                          decoration: const InputDecoration(
                            hintText: 'Nhập ghi chú…',
                          ),
                          maxLines: 3,
                          onChanged: (v) => draft.notes = v,
                        ),
                      ],
                    ),
                    if (_controller.error != null) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _controller.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            bottomNavigationBar: Material(
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFE5EAED))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.onDelete != null)
                        TextButton.icon(
                          onPressed: _controller.saving
                              ? null
                              : widget.onDelete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Xóa'),
                        ),
                      const Spacer(),
                      if (!widget.embedded)
                        OutlinedButton(
                          onPressed: _controller.saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Hủy'),
                        ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _controller.saving ? null : _save,
                        icon: _controller.saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(
                          widget.existing == null
                              ? 'Lưu và chọn'
                              : 'Lưu thay đổi',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _field(
    String key,
    String label,
    ValueChanged<String> onChanged, {
    TextInputType? keyboard,
  }) => TextFormField(
    key: ValueKey(key),
    initialValue: switch (key) {
      'directory-phone' => _controller.draft.phone,
      'directory-address' => _controller.draft.address,
      'directory-tax' => _controller.draft.taxCode,
      'directory-representative' => _controller.draft.representative,
      'directory-plate' => _controller.draft.plate,
      _ => '',
    },
    enabled: !_controller.saving,
    decoration: InputDecoration(labelText: label),
    keyboardType: keyboard,
    onChanged: onChanged,
  );
}
