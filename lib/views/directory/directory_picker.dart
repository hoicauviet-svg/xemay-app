import 'package:flutter/material.dart';
import '../../controllers/directory_controller.dart';
import '../../models/directory/directory_models.dart';
import 'directory_editor_popup.dart';

class DirectoryPicker extends StatefulWidget {
  const DirectoryPicker({
    super.key,
    required this.directory,
    required this.kind,
    required this.fieldKey,
    required this.onSelected,
    required this.onTextChanged,
    this.selectedId,
    this.initialName = '',
    this.requiredSelection = true,
  });
  final DirectoryController directory;
  final DirectoryKind kind;
  final String fieldKey, initialName;
  final String? selectedId;
  final bool requiredSelection;
  final ValueChanged<DirectoryEntry> onSelected;
  final ValueChanged<String> onTextChanged;
  @override
  State<DirectoryPicker> createState() => _DirectoryPickerState();
}

class _DirectoryPickerState extends State<DirectoryPicker> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialName);
  }

  @override
  void didUpdateWidget(covariant DirectoryPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialName != widget.initialName &&
        _text.text != widget.initialName) {
      _text.value = TextEditingValue(
        text: widget.initialName,
        selection: TextSelection.collapsed(offset: widget.initialName.length),
      );
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    _focus.unfocus();
    final entry = await showDialog<DirectoryEntry>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DirectoryEditorPopup(
        directory: widget.directory,
        kind: widget.kind,
        initialName: _text.text.trim(),
      ),
    );
    if (entry == null || !mounted) return;
    _text.value = TextEditingValue(
      text: entry.name,
      selection: TextSelection.collapsed(offset: entry.name.length),
    );
    widget.onSelected(entry);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.directory,
    builder: (context, _) {
      final theme = Theme.of(context);
      final textStyle = theme.textTheme.bodyLarge!;
      final lineHeight =
          (MediaQuery.textScalerOf(context).scale(textStyle.fontSize ?? 16) *
                  (textStyle.height ?? 1.5))
              .ceilToDouble();
      final controlHeight = (lineHeight + 24).clamp(48.0, double.infinity);
      final verticalPadding = (controlHeight - lineHeight) / 2;
      return Theme(
        data: theme.copyWith(visualDensity: VisualDensity.standard),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RawAutocomplete<DirectoryEntry>(
                textEditingController: _text,
                focusNode: _focus,
                displayStringForOption: (entry) => entry.name,
                optionsBuilder: (value) async {
                  await widget.directory.ensureLoaded(widget.kind);
                  if (!mounted) return const <DirectoryEntry>[];
                  return widget.directory.search(widget.kind, value.text);
                },
                onSelected: widget.onSelected,
                fieldViewBuilder: (context, text, focus, submit) => TextFormField(
                  key: ValueKey(widget.fieldKey),
                  controller: text,
                  focusNode: focus,
                  style: textStyle,
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    labelText: widget.kind.label,
                    helperText: widget.directory.errorFor(widget.kind),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: verticalPadding,
                    ),
                  ),
                  validator: (value) {
                    if (!widget.requiredSelection &&
                        (value ?? '').trim().isEmpty) {
                      return null;
                    }
                    if (widget.selectedId == null ||
                        value?.trim() != widget.initialName.trim()) {
                      return 'Chọn ${widget.kind.label.toLowerCase()} từ gợi ý hoặc bấm +';
                    }
                    return null;
                  },
                  onChanged: widget.onTextChanged,
                  onFieldSubmitted: (_) => submit(),
                ),
                optionsViewBuilder: (context, onSelected, options) {
                  final entries = options.toList();
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        width: MediaQuery.sizeOf(context).width < 500
                            ? 280
                            : 420,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: entries.length,
                            itemBuilder: (context, index) => ListTile(
                              key: ValueKey(
                                'directory-option-${widget.kind.name}-${entries[index].id}',
                              ),
                              title: Text(entries[index].name),
                              subtitle: Text(entries[index].subtitle),
                              onTap: () => onSelected(entries[index]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: controlHeight,
              height: controlHeight,
              child: IconButton.filled(
                key: ValueKey('directory-add-${widget.kind.name}'),
                tooltip:
                    'Thêm ${widget.kind == DirectoryKind.partner ? 'đối tác / nhà cung cấp' : 'vận chuyển'}',
                onPressed: _add,
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  fixedSize: Size.square(controlHeight),
                  minimumSize: Size.square(controlHeight),
                  maximumSize: Size.square(controlHeight),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
