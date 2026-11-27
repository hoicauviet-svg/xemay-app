import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/history/change_history_entry.dart';
import '../../models/repositories/change_history_repository.dart';
import '../../services/change_history.dart';
import '../../services/mongo_change_history_repository.dart';
import '../widgets/scrollable_data_table.dart';

const _muted = Color(0xFF6E7D83);

class ChangeHistoryTab extends StatefulWidget {
  const ChangeHistoryTab({super.key, this.repository});
  final ChangeHistoryRepository? repository;

  @override
  State<ChangeHistoryTab> createState() => _ChangeHistoryTabState();
}

class _ChangeHistoryTabState extends State<ChangeHistoryTab> {
  late final ChangeHistoryRepository _repository;
  late final bool _ownsRepository;
  final _search = TextEditingController();
  List<ChangeHistoryEntry> _rows = const [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ownsRepository = widget.repository == null;
    _repository = widget.repository ?? MongoChangeHistoryRepository();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    if (_ownsRepository) unawaited(_repository.close());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _repository.fetch(search: _search.text, limit: 200);
      if (!mounted) return;
      setState(() {
        _rows = [for (final row in rows) ChangeHistoryEntry(row)];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Chưa tải được lịch sử thay đổi. Vui lòng thử lại.';
      });
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: TextField(
                  controller: _search,
                  textAlignVertical: TextAlignVertical.center,
                  onChanged: _searchChanged,
                  decoration: const InputDecoration(
                    hintText:
                        'Tìm theo đối tượng, nội dung, máy hoặc mã yêu cầu…',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Tải lại lịch sử',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _content()),
        const SizedBox(height: 8),
        Text(
          '${_rows.length} thay đổi gần nhất. Lịch sử chỉ đọc, dùng để đối chiếu khi cần sửa dữ liệu.',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('Thử lại')),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _search.text.trim().isEmpty
              ? 'Chưa có lịch sử thay đổi.'
              : 'Không tìm thấy thay đổi phù hợp.',
        ),
      );
    }
    return ScrollableDataTable(
      fixedHeader: true,
      fitWidth: true,
      columnWidths: const [140, 150, 140, 90, 360, 180],
      columns: const [
        DataColumn(label: Text('THỜI GIAN')),
        DataColumn(label: Text('HÀNH ĐỘNG')),
        DataColumn(label: Text('LOẠI')),
        DataColumn(label: Text('ĐỐI TƯỢNG')),
        DataColumn(label: Text('NỘI DUNG')),
        DataColumn(label: Text('MÁY')),
      ],
      rows: [
        for (final entry in _rows)
          DataRow(
            onSelectChanged: (_) => _showDetails(entry),
            cells: [
              DataCell(Text(_time(entry.at))),
              DataCell(Text(_actionLabel(entry.action))),
              DataCell(Text(ChangeHistory.kindLabel(entry.kind))),
              DataCell(Text('#${entry.parentId ?? ''}')),
              DataCell(
                SizedBox(
                  width: 340,
                  child: Text(
                    entry.summary.isEmpty ? '—' : entry.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                Text(
                  entry.machine.isEmpty ? '—' : entry.machine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _time(DateTime? value) => value == null
      ? '—'
      : DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());

  String _actionLabel(String action) => switch (action) {
    'edit' => 'Sửa',
    'delete' => 'Xóa',
    'cancel' => 'Hủy đơn hàng',
    'removeLine' => 'Xóa dòng',
    'deleteCost' => 'Xóa chi phí',
    'paymentEdit' => 'Sửa phiếu trả nợ',
    'paymentDelete' => 'Xóa phiếu trả nợ',
    'merge' => 'Gộp khách hàng',
    _ => action.isEmpty ? '—' : action,
  };

  Future<void> _showDetails(ChangeHistoryEntry entry) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(entry.summary.isEmpty ? 'Chi tiết thay đổi' : entry.summary),
      content: SizedBox(
        width: 720,
        height: 560,
        child: ListView(
          children: [
            _field('Thời gian', _time(entry.at)),
            _field('Hành động', _actionLabel(entry.action)),
            _field('Loại', ChangeHistory.kindLabel(entry.kind)),
            _field('Đối tượng', '#${entry.parentId ?? ''}'),
            _field('Nguồn', entry.source),
            _field('Máy', entry.machine),
            _field('Nền tảng', '${entry.platform} · ${entry.appVersion}'),
            _field('Mã yêu cầu', entry.requestId),
            const Text(
              'Dùng mã yêu cầu để đối chiếu kế hoạch trong _record_changes và bản sao lưu trong _record_change_backups khi cần sửa dữ liệu.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (entry.before != null)
              _jsonSection('Trước khi thay đổi', entry.before!),
            if (entry.after != null)
              _jsonSection('Sau khi thay đổi', entry.after!),
            if (entry.changes.isNotEmpty)
              _jsonSection('Các bước đã ghi', {'Changes': entry.changes}),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: _muted)),
        ),
        Expanded(child: SelectableText(value.isEmpty ? '—' : value)),
      ],
    ),
  );

  Widget _jsonSection(String title, Map<String, dynamic> value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5EAED)),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(_plain(value)),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    ),
  );

  dynamic _plain(dynamic value) {
    if (value == null || value is num || value is String || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return {
        for (final entry in value.entries) '${entry.key}': _plain(entry.value),
      };
    }
    if (value is List) return [for (final item in value) _plain(item)];
    return '$value';
  }
}
