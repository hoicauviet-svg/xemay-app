import 'package:flutter/material.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../models/finance/cash_category.dart';
import '../../models/repositories/finance_repository.dart';
import '../widgets/form_popup.dart';

class CashCategoriesPopup extends StatefulWidget {
  const CashCategoriesPopup({
    super.key,
    required this.repository,
    this.initialIncome = false,
  });
  final FinanceRepository repository;
  final bool initialIncome;
  @override
  State<CashCategoriesPopup> createState() => _CashCategoriesPopupState();
}

class _CashCategoriesPopupState extends State<CashCategoriesPopup>
    with SingleTickerProviderStateMixin {
  List<CashCategory>? _rows;
  String? _error;
  bool _busy = false;
  late bool _income;
  late final TabController _tabs;
  @override
  void initState() {
    super.initState();
    _income = widget.initialIncome;
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: _income ? 0 : 1,
    );
    _tabs.addListener(() {
      final income = _tabs.index == 0;
      if (income != _income) setState(() => _income = income);
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.repository.categories();
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Chưa tải được danh mục.');
    }
  }

  Future<void> _edit([CashCategory? category]) async {
    var name = category?.name ?? '';
    final income = category?.income ?? _income;
    final result = await showDialog<CashCategory>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null ? 'Thêm danh mục' : 'Sửa danh mục'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: name,
                onChanged: (value) => name = value,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Tên danh mục'),
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Loại phiếu'),
                child: Text(income ? 'Thu' : 'Chi'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) {
                Navigator.pop(
                  context,
                  CashCategory(
                    category?.id ?? ObjectId().oid,
                    name.trim(),
                    income,
                  ),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (result != null) {
      await _run(() => widget.repository.saveCategory(result));
    }
  }

  Future<void> _archive(CashCategory category) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ngừng sử dụng danh mục'),
        content: Text(
          'Ngừng sử dụng “${category.name}”? Các phiếu đã ghi nhận vẫn được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ngừng sử dụng'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _run(() => widget.repository.archiveCategory(category.id));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Chưa lưu được danh mục. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows?.where((c) => c.income == _income).toList();
    return FormPopup(
      title: 'Danh mục thu/chi',
      canClose: !_busy,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AbsorbPointer(
                    absorbing: _busy,
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      labelColor: const Color(0xFF176455),
                      indicatorColor: const Color(0xFF176455),
                      tabs: const [
                        Tab(text: 'Thu'),
                        Tab(text: 'Chi'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.add),
                  label: Text(
                    _income ? 'Thêm danh mục thu' : 'Thêm danh mục chi',
                  ),
                ),
              ],
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE5EAED)),
            if (_error != null) Text(_error!),
            Expanded(
              child: _rows == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: rows!.length,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        return ListTile(
                          title: Text(row.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Sửa',
                                onPressed: _busy ? null : () => _edit(row),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Ngừng sử dụng',
                                onPressed: _busy ? null : () => _archive(row),
                                icon: const Icon(Icons.archive_outlined),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
