import 'package:flutter/material.dart';
import '../../models/maintenance/record_maintenance.dart';
import '../../services/mongo_record_maintenance.dart';
import '../widgets/form_popup.dart';

/// Opening this view only reads pending changes. Each continuation is explicit.
class RecordRecoveryButton extends StatelessWidget {
  const RecordRecoveryButton({super.key, this.repository, this.onChanged});
  final RecordMaintenance? repository;
  final Future<void> Function()? onChanged;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Tiếp tục xử lý thay đổi dang dở',
    icon: const Icon(Icons.restore),
    onPressed: () async {
      final source = repository ?? MongoRecordMaintenance.local();
      try {
        final changed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _RecoveryView(repository: source),
        );
        if (changed == true && context.mounted) await onChanged?.call();
      } finally {
        if (repository == null) await source.close();
      }
    },
  );
}

class _RecoveryView extends StatefulWidget {
  const _RecoveryView({required this.repository});
  final RecordMaintenance repository;
  @override
  State<_RecoveryView> createState() => _RecoveryViewState();
}

class _RecoveryViewState extends State<_RecoveryView> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _busy = false, _changed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.repository.pending();
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không tải được danh sách. Vui lòng thử lại.';
        });
      }
    }
  }

  Future<void> _continue(Map<String, dynamic> row) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final kind = RecordKind.values.byName(row['Kind'] as String);
      await widget.repository.recover(kind, row['Parent'] as int);
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: FormPopup(
      title: 'Thay đổi chưa hoàn tất',
      canClose: !_busy,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Chọn Tiếp tục xử lý để hoàn thành thay đổi đã xác nhận trước đó.',
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? const Center(child: Text('Không có thay đổi dang dở.'))
                  : ListView(
                      children: [
                        for (final row in _rows)
                          ListTile(
                            title: Text(
                              '${switch (row['Kind']) {
                                'order' => 'Đơn hàng',
                                'batch' => 'Lô hàng',
                                'pawn' => 'Cầm đồ',
                                'funding' => 'Vay vốn',
                                'vehicleProduct' => 'Xe',
                                'partProduct' => 'Phụ tùng',
                                'cash' => 'Thu chi',
                                _ => 'Nợ cũ',
                              }} #${row['Parent']}',
                            ),
                            subtitle: Text(
                              row['DeleteParent'] == true
                                  ? 'Đang xóa phiếu'
                                  : 'Đang cập nhật phiếu',
                            ),
                            trailing: FilledButton(
                              onPressed: _busy ? null : () => _continue(row),
                              child: const Text('Tiếp tục xử lý'),
                            ),
                          ),
                      ],
                    ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_error != null)
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Tải lại'),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(context, _changed),
                child: const Text('Đóng'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
