import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/customers/customer_duplicates.dart';
import '../../models/customers/customer_models.dart';
import '../../models/repositories/customer_repository.dart';
import '../../services/mongo_customer_repository.dart';

class CustomerMergeTab extends StatefulWidget {
  const CustomerMergeTab({super.key, this.repository});
  final CustomerRepository? repository;
  @override
  State<CustomerMergeTab> createState() => _CustomerMergeTabState();
}

class _CustomerMergeTabState extends State<CustomerMergeTab>
    with AutomaticKeepAliveClientMixin {
  late final CustomerRepository _repository;
  final _selected = <int, Map<String, dynamic>>{};
  int? _target;
  TabController? _tabs;
  bool _active = false;
  bool _saving = false, _interrupted = false, _loading = true;
  String? _error;
  String _search = '';
  static const _groupsPerPage = 10;
  int _page = 0;
  List<Map<String, dynamic>> _rows = [], _pending = [];
  List<CustomerDuplicateGroup> _groups = [];
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MongoCustomerRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _repository.mergeCandidates();
      final pending = await _repository.pendingMerges();
      if (!mounted) return;
      setState(() {
        if (!_interrupted) {
          final byId = {for (final row in rows) row['IdKH']: row};
          _selected.removeWhere((id, _) => !byId.containsKey(id));
          for (final id in _selected.keys.toList()) {
            _selected[id] = byId[id]!;
          }
          if (!_selected.containsKey(_target)) {
            _target = _selected.keys.firstOrNull;
          }
        }
        _rows = rows;
        _groups = findCustomerDuplicates(rows);
        _page = 0;
        _pending = pending;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không tải được danh sách khách trùng. Vui lòng thử lại.';
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = DefaultTabController.maybeOf(context);
    if (_tabs != tabs) {
      _tabs?.removeListener(_tabChanged);
      _tabs = tabs;
      _active = tabs == null || tabs.index == 1;
      tabs?.addListener(_tabChanged);
    }
  }

  void _tabChanged() {
    final active = _tabs?.index == 1;
    if (active && !_active && !_saving && !_loading) unawaited(_load());
    _active = active;
  }

  @override
  void dispose() {
    _tabs?.removeListener(_tabChanged);
    unawaited(_repository.close());
    super.dispose();
  }

  void _select(Map<String, dynamic> row, bool checked) {
    final id = row['IdKH'] as int;
    if (checked) {
      _selected[id] = row;
      _target ??= id;
    } else {
      _selected.remove(id);
      if (_target == id) _target = _selected.keys.firstOrNull;
    }
  }

  void _resume(Map<String, dynamic> request) {
    setState(() {
      _selected.clear();
      for (final row in request['BanGoc'] as List) {
        _selected[row['IdKH'] as int] = Map<String, dynamic>.from(row as Map);
      }
      _target = request['KhachChinh'] as int;
      _interrupted = true;
      _error = 'Lần gộp trước chưa hoàn tất. Bấm Thử lại để tiếp tục.';
    });
  }

  Future<void> _merge() async {
    final target = _selected[_target]!;
    final others = _selected.entries.where((e) => e.key != _target).toList();
    if (!_interrupted) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Xác nhận gộp khách hàng'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Text(
                'Giữ khách chính: #$_target — ${target['TenKhachHang']}\n\n'
                'Gộp các khách sau:\n${others.map((e) => '#${e.key} — ${e.value['TenKhachHang']}').join('\n')}\n\n'
                'Chuyển toàn bộ đơn hàng, phiếu cầm đồ và nợ cũ sang khách chính. Giữ nguyên thông tin khách chính và số tiền các phiếu. Khách trùng được ẩn, thông tin gốc được lưu để đối chiếu.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Xác nhận gộp'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repository.merge(
        targetId: _target!,
        sourceIds: others.map((e) => e.key).toList(),
      );
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _target = null;
        _interrupted = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gộp khách hàng thành công')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _interrupted = true;
          _error =
              '${e is CustomerException ? e.message : 'Chưa hoàn tất gộp khách hàng.'} Bấm Thử lại để tiếp tục cùng danh sách đã chọn.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final searching = _search.trim().isNotEmpty;
    final matches = searching
        ? searchCustomers(_rows, _search)
        : <Map<String, dynamic>>[];
    final pageSize = searching ? 30 : _groupsPerPage;
    final total = searching ? matches.length : _groups.length;
    final pageCount = ((total + pageSize - 1) ~/ pageSize).clamp(1, 1 << 30);
    final page = _page.clamp(0, pageCount - 1);
    final pageGroups = _groups.skip(page * pageSize).take(pageSize).toList();
    final pageRows = searching
        ? matches.skip(page * pageSize).take(pageSize).toList()
        : [for (final group in pageGroups) ...group.customers];
    final visible = <int, Map<String, dynamic>>{
      for (final row in pageRows) row['IdKH'] as int: row,
    };
    final selectedCount = visible.keys.where(_selected.containsKey).length;
    final items = <Object>[
      if (searching)
        ...pageRows
      else
        for (final group in pageGroups) ...[group, ...group.customers],
    ];
    final enabled = !_saving && !_interrupted && !_loading;
    return Container(
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
                    enabled: enabled,
                    onChanged: (value) => setState(() {
                      _search = value;
                      _page = 0;
                    }),
                    decoration: const InputDecoration(
                      hintText: 'Tìm mã, tên, điện thoại, địa chỉ…',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tải lại',
                onPressed: enabled ? _load : null,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (!_interrupted)
            for (final request in _pending)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : () => _resume(request),
                  icon: const Icon(Icons.restore),
                  label: Text(
                    'Tiếp tục gộp vào khách #${request['KhachChinh']}',
                  ),
                ),
              ),
          const SizedBox(height: 8),
          Row(
            children: [
              Tooltip(
                message: 'Chọn khách trên trang này',
                child: Checkbox(
                  tristate: true,
                  value: selectedCount == 0
                      ? false
                      : selectedCount == visible.length
                      ? true
                      : null,
                  onChanged: !enabled || visible.isEmpty
                      ? null
                      : (_) => setState(() {
                          final select = selectedCount != visible.length;
                          for (final row in visible.values) {
                            _select(row, select);
                          }
                        }),
                ),
              ),
              Expanded(
                child: Text(
                  searching
                      ? '${matches.length} kết quả · ${visible.length} khách trên trang'
                      : '${_groups.length} nhóm trùng cả 3 trường · ${visible.length} khách trên trang',
                ),
              ),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: !enabled
                      ? null
                      : () => setState(() {
                          _selected.clear();
                          _target = null;
                        }),
                  child: const Text('Bỏ chọn'),
                ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? Center(
                    child: Text(
                      _error ??
                          (searching
                              ? 'Không có khách hàng phù hợp.'
                              : 'Không có khách hàng trùng phù hợp.'),
                    ),
                  )
                : Material(
                    color: Colors.transparent,
                    child: ListView.builder(
                      key: ValueKey('duplicates:$page:$_search'),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        if (item is CustomerDuplicateGroup) {
                          return Container(
                            color: const Color(0xFFF2F6F5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.customers.length} khách hàng · ${item.value}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: !enabled
                                      ? null
                                      : () => setState(() {
                                          for (final row in item.customers) {
                                            _select(row, true);
                                          }
                                        }),
                                  child: const Text('Chọn nhóm'),
                                ),
                              ],
                            ),
                          );
                        }
                        final row = item as Map<String, dynamic>;
                        return CheckboxListTile(
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selected.containsKey(row['IdKH']),
                          onChanged: !enabled
                              ? null
                              : (value) =>
                                    setState(() => _select(row, value == true)),
                          title: Text(
                            '#${row['IdKH']} — ${row['TenKhachHang']}',
                          ),
                          subtitle: Text(
                            [row['SoDienThoai'], row['DiaChiHienThi']]
                                .where(
                                  (v) => v != null && '$v'.trim().isNotEmpty,
                                )
                                .join(' · '),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(searching ? '30 khách / trang' : '10 nhóm / trang'),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Trang đầu',
                onPressed: !enabled || page == 0
                    ? null
                    : () => setState(() => _page = 0),
                icon: const Icon(Icons.first_page),
              ),
              IconButton(
                tooltip: 'Trang trước',
                onPressed: !enabled || page == 0
                    ? null
                    : () => setState(() => _page = page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${page + 1} / $pageCount'),
              IconButton(
                tooltip: 'Trang sau',
                onPressed: !enabled || page + 1 >= pageCount
                    ? null
                    : () => setState(() => _page = page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Trang cuối',
                onPressed: !enabled || page + 1 >= pageCount
                    ? null
                    : () => setState(() => _page = pageCount - 1),
                icon: const Icon(Icons.last_page),
              ),
            ],
          ),
          const Divider(height: 1),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 120,
              child: Material(
                color: Colors.transparent,
                child: SingleChildScrollView(
                  child: RadioGroup<int>(
                    groupValue: _target,
                    onChanged: (value) => setState(() => _target = value),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Khách chính (giữ nguyên tên, điện thoại và địa chỉ):',
                          ),
                        ),
                        for (final row in _selected.values)
                          RadioListTile<int>(
                            value: row['IdKH'] as int,
                            enabled: !_saving && !_interrupted,
                            title: Text(
                              '#${row['IdKH']} — ${row['TenKhachHang']}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('Đã chọn ${_selected.length} khách hàng')),
              FilledButton.icon(
                onPressed: _saving || _loading || _selected.length < 2
                    ? null
                    : _merge,
                icon: const Icon(Icons.merge_type),
                label: Text(
                  _saving
                      ? 'Đang gộp…'
                      : _interrupted
                      ? 'Thử lại'
                      : 'Gộp khách hàng',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
