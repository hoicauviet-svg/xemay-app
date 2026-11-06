import 'dart:async';
import 'package:flutter/material.dart';
import '../../controllers/directory_controller.dart';
import '../../controllers/partner_controller.dart';
import '../../models/directory/directory_models.dart';
import '../../models/repositories/partner_repository.dart';
import '../../services/mongo_partner_repository.dart';
import '../widgets/scrollable_data_table.dart';
import 'directory_editor_popup.dart';
import 'partner_details_screen.dart';

class PartnerTab extends StatefulWidget {
  const PartnerTab({super.key, this.repository});
  final PartnerRepository? repository;
  @override
  State<PartnerTab> createState() => _PartnerTabState();
}

class _PartnerTabState extends State<PartnerTab> {
  late final PartnerController _controller;
  late final DirectoryController _directory;
  @override
  void initState() {
    super.initState();
    _controller = PartnerController(
      widget.repository ?? MongoPartnerRepository(),
    );
    _directory = DirectoryController(_controller.repository);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _directory.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _value(dynamic v) =>
      v == null || v.toString().trim().isEmpty ? '—' : v.toString();
  void _open(Map<String, dynamic> row) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PartnerDetailsScreen(
        partnerId: row['_id'] as String,
        repository: _controller.repository,
      ),
    ),
  );
  DirectoryEntry _entry(Map<String, dynamic> r) => DirectoryEntry(
    id: r['_id'] as String,
    kind: DirectoryKind.partner,
    name: '${r['TenDoiTac'] ?? ''}',
    phone: '${r['SoDienThoai'] ?? ''}',
    address: '${r['DiaChi'] ?? ''}',
    taxCode: '${r['MaSoThue'] ?? ''}',
    representative: '${r['NguoiDaiDien'] ?? ''}',
    notes: '${r['GhiChu'] ?? ''}',
  );
  Future<void> _edit(Map<String, dynamic> row) async {
    final saved = await showDialog<DirectoryEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DirectoryEditorPopup(
        directory: _directory,
        kind: DirectoryKind.partner,
        existing: _entry(row),
      ),
    );
    if (saved != null && mounted) {
      await _controller.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật đối tác thành công')),
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa đối tác'),
        content: Text(
          'Xóa "${row['TenDoiTac']}" khỏi danh bạ? Lịch sử nhập hàng và công nợ vẫn được giữ nguyên.',
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
    if (yes != true) return;
    try {
      await _directory.delete(_entry(row));
      if (mounted) await _controller.load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không xóa được đối tác. Vui lòng thử lại.'),
          ),
        );
      }
    }
  }

  Widget _actions(Map<String, dynamic> row) => IconButtonTheme(
    data: IconButtonThemeData(
      style: IconButton.styleFrom(
        fixedSize: const Size.square(36),
        minimumSize: const Size.square(36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Cập nhật đối tác',
          onPressed: () => _edit(row),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Xóa đối tác',
          onPressed: () => _delete(row),
          icon: const Icon(Icons.delete_outline, color: Color(0xFFB44141)),
        ),
      ],
    ),
  );
  Future<void> _add() async {
    final saved = await showDialog<DirectoryEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DirectoryEditorPopup(
        directory: _directory,
        kind: DirectoryKind.partner,
      ),
    );
    if (saved != null && mounted) await _controller.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EAED)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    onChanged: _controller.searchChanged,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: const InputDecoration(
                      hintText: 'Tìm tên, điện thoại, địa chỉ, mã số thuế…',
                      prefixIcon: Icon(Icons.search),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                tooltip: 'Thêm đối tác',
                onPressed: _add,
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(48),
                  minimumSize: const Size.square(48),
                  maximumSize: const Size.square(48),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _body()),
          if (!_controller.loading && _controller.error == null)
            Row(
              children: [
                Expanded(child: Text('${_controller.data!.total} đối tác')),
                IconButton(
                  tooltip: 'Trang đối tác trước',
                  onPressed: _controller.page > 0
                      ? () => _controller.goToPage(_controller.page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${_controller.page + 1} / ${_controller.pageCount}'),
                IconButton(
                  tooltip: 'Trang đối tác sau',
                  onPressed: _controller.page + 1 < _controller.pageCount
                      ? () => _controller.goToPage(_controller.page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    ),
  );
  Widget _body() {
    if (_controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_controller.error!),
            TextButton(
              onPressed: _controller.load,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    final rows = _controller.data!.rows;
    if (rows.isEmpty) {
      return const Center(child: Text('Không có đối tác phù hợp.'));
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 700) {
          return ListView(
            children: [
              for (final r in rows)
                ListTile(
                  onTap: () => _open(r),
                  title: Text(_value(r['TenDoiTac'])),
                  subtitle: Text(
                    '${_value(r['SoDienThoai'])}\n${_value(r['DiaChi'])}',
                  ),
                  isThreeLine: true,
                  trailing: _actions(r),
                ),
            ],
          );
        }
        return ScrollableDataTable(
          fixedHeader: true,
          fitWidth: true,
          columnWidths: const [220, 150, 260, 160, 180, 112],
          columns: const [
            DataColumn(label: Text('TÊN ĐỐI TÁC')),
            DataColumn(label: Text('ĐIỆN THOẠI')),
            DataColumn(label: Text('ĐỊA CHỈ')),
            DataColumn(label: Text('MÃ SỐ THUẾ')),
            DataColumn(label: Text('NGƯỜI ĐẠI DIỆN')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                onSelectChanged: (_) => _open(r),
                cells: [
                  for (final f in [
                    'TenDoiTac',
                    'SoDienThoai',
                    'DiaChi',
                    'MaSoThue',
                    'NguoiDaiDien',
                  ])
                    DataCell(Text(_value(r[f]))),
                  DataCell(_actions(r)),
                ],
              ),
          ],
        );
      },
    );
  }
}
