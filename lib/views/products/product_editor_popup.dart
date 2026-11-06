import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/products/product_details.dart';
import '../../core/formatters/money_input_formatter.dart';
import '../widgets/editor_shell.dart';
import '../widgets/form_section.dart';

class ProductEditorPopup extends StatefulWidget {
  const ProductEditorPopup({
    super.key,
    this.embedded = false,
    this.onSaved,
    this.onDelete,
    required this.product,
    required this.information,
    required this.onSave,
  });
  final ProductReference product;
  final Map<String, dynamic> information;
  final Future<void> Function(ProductEditDraft) onSave;
  final bool embedded;
  final Future<void> Function()? onSaved;
  final Future<void> Function()? onDelete;
  @override
  State<ProductEditorPopup> createState() => _ProductEditorPopupState();
}

class _ProductEditorPopupState extends State<ProductEditorPopup> {
  late final ProductEditDraft draft;
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    draft = ProductEditDraft.fromInformation(
      widget.information,
      widget.product.vehicle,
    );
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(draft);
      if (mounted) {
        if (widget.embedded) {
          setState(() => saving = false);
          await widget.onSaved?.call();
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is StateError
              ? e.message
              : 'Không lưu được sản phẩm. Vui lòng thử lại.';
        });
      }
    }
  }

  Widget field(
    String label,
    String value,
    ValueChanged<String> changed, {
    bool required = false,
    bool enabled = true,
    bool money = false,
  }) => TextFormField(
    initialValue: money ? groupMoney(value) : value,
    enabled: !saving && enabled,
    decoration: InputDecoration(
      labelText: label,
      suffixText: money ? 'đ' : null,
    ),
    keyboardType: money ? TextInputType.number : null,
    inputFormatters: money
        ? <TextInputFormatter>[const MoneyInputFormatter()]
        : null,
    validator: (v) {
      if (required && (v ?? '').trim().isEmpty) return 'Vui lòng nhập $label';
      if (money && (v ?? '').isNotEmpty) {
        final n = int.tryParse(ungroupMoney(v!));
        if (n == null || n < 0 || n > 1000000000000000) {
          return 'Giá bán không hợp lệ';
        }
      }
      return null;
    },
    onChanged: (v) => changed(money ? ungroupMoney(v) : v),
  );
  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      field('Tên sản phẩm', draft.name, (v) => draft.name = v, required: true),
      field(
        'Giá bán',
        draft.salePrice,
        (v) => draft.salePrice = v,
        money: true,
        enabled:
            !widget.product.vehicle || widget.information['TinhTrang'] != false,
      ),
      if (widget.product.vehicle) ...[
        field('Số khung', draft.frame, (v) => draft.frame = v),
        field('Số máy', draft.engine, (v) => draft.engine = v),
        field('Biển số', draft.plate, (v) => draft.plate = v),
      ] else ...[
        field('Mã sản phẩm', draft.code, (v) => draft.code = v),
        field('Đơn vị tính', draft.unit, (v) => draft.unit = v),
      ],
      field('Ghi chú', draft.notes, (v) => draft.notes = v),
    ];
    return PopScope(
      canPop: !saving,
      child: EditorShell(
        embedded: widget.embedded,
        title: 'Cập nhật sản phẩm',
        canClose: !saving,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Form(
            key: form,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FormSection(
                title: 'Thông tin sản phẩm',
                children: [
                  ResponsiveFormFields(fields: fields),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onDelete != null)
                  TextButton.icon(
                    onPressed: saving ? null : widget.onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Xóa sản phẩm'),
                  ),
                const Spacer(),
                if (!widget.embedded)
                  OutlinedButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Đang lưu…' : 'Lưu thay đổi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
