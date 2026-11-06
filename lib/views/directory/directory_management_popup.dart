import 'package:flutter/material.dart';
import '../../controllers/directory_controller.dart';
import '../../models/directory/directory_models.dart';
import '../widgets/form_popup.dart';
import 'directory_editor_popup.dart';

class DirectoryManagementPopup extends StatefulWidget {
  const DirectoryManagementPopup({
    super.key,
    required this.directory,
    required this.kind,
    this.embedded = false,
  });
  final DirectoryController directory;
  final DirectoryKind kind;
  final bool embedded;
  @override
  State<DirectoryManagementPopup> createState() =>
      _DirectoryManagementPopupState();
}

class _DirectoryManagementPopupState extends State<DirectoryManagementPopup> {
  List<DirectoryEntry> entries = [];
  String search = '';
  String? error;
  bool loading = true, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await widget.directory.repository.fetch(widget.kind);
      if (mounted) {
        setState(() {
          entries = rows;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Không tải được danh sách. Vui lòng thử lại.';
        });
      }
    }
  }

  Future<void> edit([DirectoryEntry? entry]) async {
    final saved = await showDialog<DirectoryEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DirectoryEditorPopup(
        directory: widget.directory,
        kind: widget.kind,
        existing: entry,
      ),
    );
    if (saved != null && mounted) {
      await load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu thông tin')));
      }
    }
  }

  Future<void> remove(DirectoryEntry entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Xóa ${widget.kind.label.toLowerCase()}'),
        content: Text(
          'Xóa "${entry.name}" khỏi danh bạ? Lịch sử giao dịch vẫn được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.directory.delete(entry);
      await load();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Không xóa được thông tin. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = entries.where((e) => e.matches(search)).toList();
    final content = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Tìm tên, điện thoại, biển số…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(48),
                  minimumSize: const Size.square(48),
                  maximumSize: const Size.square(48),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                tooltip: 'Thêm ${widget.kind.label.toLowerCase()}',
                onPressed: busy ? null : () => edit(),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (error != null)
            TextButton(onPressed: load, child: const Text('Thử lại')),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? const Center(child: Text('Không có thông tin phù hợp.'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (c, i) {
                      final entry = rows[i];
                      return ListTile(
                        title: Text(entry.name),
                        subtitle: Text(
                          [
                            entry.phone,
                            entry.plate,
                            entry.notes,
                          ].where((v) => v.isNotEmpty).join(' · '),
                        ),
                        onTap: busy ? null : () => edit(entry),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Cập nhật',
                              onPressed: busy ? null : () => edit(entry),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Xóa',
                              onPressed: busy ? null : () => remove(entry),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Color(0xFFB44141),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
    if (widget.embedded) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5EAED)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: content,
        ),
      );
    }
    return PopScope(
      canPop: !busy,
      child: FormPopup(
        title: widget.kind.label,
        canClose: !busy,
        child: content,
      ),
    );
  }
}
