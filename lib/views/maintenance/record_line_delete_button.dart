import 'package:flutter/material.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../models/maintenance/record_maintenance.dart';

class RecordLineDeleteButton extends StatefulWidget {
  const RecordLineDeleteButton({
    super.key,
    required this.repository,
    required this.kind,
    required this.parentId,
    required this.lineId,
    required this.onChanged,
  });
  final RecordMaintenance? repository;
  final RecordKind kind;
  final int parentId;
  final dynamic lineId;
  final Future<void> Function() onChanged;
  @override
  State<RecordLineDeleteButton> createState() => _RecordLineDeleteButtonState();
}

class _RecordLineDeleteButtonState extends State<RecordLineDeleteButton> {
  bool _busy = false;
  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa sản phẩm khỏi phiếu'),
        content: const Text(
          'Xóa dòng sản phẩm này và cập nhật tổng tiền, công nợ, tồn kho tương ứng?',
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
    setState(() => _busy = true);
    try {
      await widget.repository!.removeLine(
        widget.kind,
        widget.parentId,
        widget.lineId,
        requestId: ObjectId().oid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa sản phẩm khỏi phiếu')),
        );
        await widget.onChanged();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Xóa sản phẩm khỏi phiếu',
    onPressed: _busy || widget.repository == null ? null : _remove,
    icon: const Icon(Icons.delete_outline, color: Color(0xFFB44141)),
  );
}
