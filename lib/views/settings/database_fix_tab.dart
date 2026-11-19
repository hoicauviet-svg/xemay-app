import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../controllers/cart_controller.dart';
import '../../core/config/database_config.dart';
import '../../services/database_fix_service.dart';
import '../../services/stuck_order_repair.dart';
import '../widgets/form_section.dart';

const _fixTypes = XTypeGroup(
  label: 'Lệnh sửa dữ liệu',
  extensions: ['json', 'txt'],
  uniformTypeIdentifiers: ['public.json', 'public.plain-text'],
);

const _updateTemplate = '''[
  {
    "collection": "HoaDonBan",
    "filter": {"IdHoaDon": 0},
    "update": {
      "\$set": {"SoTienKhachDua": 0, "TienThua": 0}
    },
    "note": "Sửa tiền khách đưa và tiền thừa (đổi IdHoaDon)"
  }
]''';

const _deleteTemplate = '''[
  {
    "collection": "TraNo",
    "filter": {"IdTraNo": 0},
    "delete": true,
    "note": "Xóa một phiếu trả nợ sai (đổi IdTraNo)"
  }
]''';

const _insertTemplate = '''[
  {
    "collection": "TraNo",
    "insert": {
      "IdTraNo": 0,
      "IdSoNo": 0,
      "NgayTra": {"\$date": "2026-11-19T00:00:00Z"},
      "SotienTra": 100000,
      "LaiThu": 0,
      "GhiChu": "Phiếu bổ sung"
    },
    "note": "Chèn một phiếu còn thiếu (đổi các Id)"
  }
]''';

class DatabaseFixTab extends StatefulWidget {
  const DatabaseFixTab({
    super.key,
    this.runnerFactory,
    this.stuckRunnerFactory,
  });
  final DatabaseFixRunner Function()? runnerFactory;
  final StuckOrderRunner Function()? stuckRunnerFactory;
  @override
  State<DatabaseFixTab> createState() => _DatabaseFixTabState();
}

class _DatabaseFixTabState extends State<DatabaseFixTab> {
  final _script = TextEditingController();
  bool _busy = false;
  String? _error, _info;
  DatabaseFixPreview? _preview;
  DatabaseFixRun? _run;
  StuckOrderScan? _stuckScan;
  StuckOrderRepairRun? _stuckRun;
  bool _stuckBusy = false;
  String? _stuckError;

  @override
  void dispose() {
    _script.dispose();
    super.dispose();
  }

  String get _target {
    final uri = Uri.tryParse(DatabaseConfig.mongoUri);
    if (uri == null) return 'database đang dùng';
    final database = uri.pathSegments.firstWhere(
      (part) => part.isNotEmpty,
      orElse: () => '',
    );
    final host = uri.host.isEmpty ? 'máy chủ đã cấu hình' : uri.host;
    final cloud = uri.scheme == 'mongodb+srv' ? 'cloud ' : '';
    return '$cloud$host${database.isEmpty ? '' : '/$database'}';
  }

  String _action(DatabaseFixAction action) => switch (action) {
    DatabaseFixAction.update => 'Cập nhật',
    DatabaseFixAction.delete => 'Xóa',
    DatabaseFixAction.insert => 'Thêm',
  };

  DatabaseFixPlan? _parse() {
    try {
      return DatabaseFixService.parse(_script.text);
    } on DatabaseFixFormatException catch (error) {
      setState(() {
        _error = error.message;
        _preview = null;
      });
      return null;
    }
  }

  DatabaseFixRunner _runner() =>
      widget.runnerFactory?.call() ?? DatabaseFixService.local();

  Future<void> _previewNow() async {
    if (_busy) return;
    final plan = _parse();
    if (plan == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _run = null;
    });
    final runner = _runner();
    try {
      final preview = await runner.preview(plan);
      if (!mounted) return;
      setState(() => _preview = preview);
    } on DatabaseFixFormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Chưa kiểm tra được: $error');
    } finally {
      await runner.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _execute() async {
    if (_busy) return;
    final plan = _parse();
    if (plan == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _run = null;
    });
    final runner = _runner();
    try {
      final preview = await runner.preview(plan);
      if (!mounted) return;
      // Stop the progress indicator before opening the dialog.
      setState(() => _busy = false);
      final confirmed = await _confirm(plan, preview);
      if (confirmed != true || !mounted) return;
      setState(() {
        _busy = true;
        _preview = preview;
      });
      final run = await runner.execute(plan, script: _script.text);
      if (!mounted) return;
      setState(() {
        _run = run;
        _info = run.historyError == null
            ? null
            : 'Không ghi được lịch sử sửa dữ liệu: ${run.historyError}';
      });
    } on DatabaseFixFormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Chưa thực thi được: $error');
    } finally {
      await runner.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  StuckOrderRunner _stuckRunner() =>
      widget.stuckRunnerFactory?.call() ?? StuckOrderRepair.local();

  Future<void> _scanStuck() async {
    if (_stuckBusy) return;
    setState(() {
      _stuckBusy = true;
      _stuckError = null;
      _stuckRun = null;
    });
    final runner = _stuckRunner();
    try {
      final scan = await runner.scan();
      if (!mounted) return;
      setState(() => _stuckScan = scan);
    } catch (error) {
      if (mounted) setState(() => _stuckError = 'Chưa quét được: $error');
    } finally {
      await runner.close();
      if (mounted) setState(() => _stuckBusy = false);
    }
  }

  Future<void> _fixStuck() async {
    final scan = _stuckScan;
    if (_stuckBusy || scan == null || !scan.hasFixable) return;
    final confirmed = await _confirmStuck(scan);
    if (confirmed != true || !mounted) return;
    setState(() {
      _stuckBusy = true;
      _stuckError = null;
      _stuckRun = null;
    });
    final runner = _stuckRunner();
    try {
      final run = await runner.repair();
      if (!mounted) return;
      setState(() {
        _stuckRun = run;
        _stuckScan = run.scan;
      });
    } catch (error) {
      if (mounted) setState(() => _stuckError = 'Chưa sửa được: $error');
    } finally {
      await runner.close();
      if (mounted) setState(() => _stuckBusy = false);
    }
  }

  Future<bool?> _confirmStuck(StuckOrderScan scan) {
    final fixable = scan.issues.where((issue) => issue.fixable).toList();
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sửa đơn kẹt?'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sẽ sửa ${fixable.length} đơn trên $_target và không thể hoàn tác. Hãy sao lưu dữ liệu trước khi tiếp tục.',
                  style: const TextStyle(color: Color(0xFFB5473D)),
                ),
                const SizedBox(height: 12),
                for (final issue in fixable.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '#${issue.orderId} · ${issue.title}\n${issue.actions.join(' ')}',
                    ),
                  ),
                if (fixable.length > 8)
                  Text('… và ${fixable.length - 8} đơn khác.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const ValueKey('stuck-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sửa đơn kẹt'),
          ),
        ],
      ),
    );
  }

  void _reload() {
    if (CartController.shared.count > 0 || CartController.shared.locked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hãy hoàn tất hoặc bỏ đơn bán hàng đang nhập trước khi tải lại dữ liệu.',
          ),
        ),
      );
      return;
    }
    DatabaseConfig.refresh();
  }

  Future<bool?> _confirm(
    DatabaseFixPlan plan,
    DatabaseFixPreview preview,
  ) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Thực thi lệnh sửa dữ liệu?'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lệnh ghi trực tiếp vào MongoDB đang dùng và không thể hoàn tác. Các lệnh chạy lần lượt, không phải transaction: nếu lỗi, các lệnh trước vẫn được giữ.',
                style: TextStyle(color: Color(0xFFB5473D)),
              ),
              const SizedBox(height: 12),
              Text('Database: $_target'),
              Text('Số lệnh: ${plan.operations.length}'),
              if (preview.warning != null) ...[
                const SizedBox(height: 8),
                Text(
                  preview.warning!,
                  style: const TextStyle(color: Color(0xFFB5473D)),
                ),
              ],
              const SizedBox(height: 12),
              for (final step in preview.steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '#${step.index} ${_action(step.action)} ${step.collection}'
                    '${step.action == DatabaseFixAction.insert ? '' : ' · khớp ${step.matched}'}',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('fix-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Thực thi'),
        ),
      ],
    ),
  );

  Future<void> _loadFile() async {
    try {
      final file = await openFile(acceptedTypeGroups: const [_fixTypes]);
      if (file == null) return;
      if (await file.length() > DatabaseFixService.maxScriptLength) {
        if (mounted) {
          setState(() => _error = 'Tệp lệnh quá lớn (tối đa 1 MB).');
        }
        return;
      }
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _script.text = text;
        _preview = null;
        _run = null;
        _error = null;
        _info = 'Đã nhập ${file.name}.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Chưa đọc được tệp: $error');
    }
  }

  Future<void> _pickTemplate() async {
    final template = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chèn mẫu lệnh'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Sửa trường của một bản ghi'),
                subtitle: const Text('update với \$set'),
                onTap: () => Navigator.pop(context, _updateTemplate),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Xóa một bản ghi sai'),
                subtitle: const Text('delete theo filter'),
                onTap: () => Navigator.pop(context, _deleteTemplate),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Chèn một bản ghi còn thiếu'),
                subtitle: const Text('insert với ngày \$date'),
                onTap: () => Navigator.pop(context, _insertTemplate),
              ),
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
    if (template == null || !mounted) return;
    setState(() {
      _script.text = template;
      _preview = null;
      _run = null;
      _error = null;
      _info = 'Đã chèn mẫu; thay các Id 0 bằng dữ liệu thật trước khi chạy.';
    });
  }

  void _clear() {
    setState(() {
      _script.clear();
      _preview = null;
      _run = null;
      _error = null;
      _info = null;
    });
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Định dạng lệnh sửa dữ liệu'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Nội dung là JSON: một mảng lệnh, một object có "operations", hoặc một lệnh đơn lẻ.',
                ),
                SizedBox(height: 12),
                Text('Mỗi lệnh có:'),
                Text('• collection: tên collection đang có trong database.'),
                Text(
                  '• filter: bắt buộc với update/delete; không cho sửa/xóa toàn bộ collection.',
                ),
                Text('• một trong: update, delete: true, insert.'),
                Text('• many: true để áp dụng cho mọi bản ghi khớp.'),
                Text(
                  '• upsert: true để chèn khi update không khớp bản ghi nào.',
                ),
                Text('• note: mô tả ngắn (không bắt buộc).'),
                SizedBox(height: 12),
                Text(
                  'update chỉ hỗ trợ \$set, \$unset, \$inc. Dùng {"\$date": "2026-11-19T00:00:00Z"} cho ngày và {"\$oid": "..."} cho ObjectId.',
                ),
                Text(
                  'Dùng số nguyên cho các trường tiền để không vi phạm ràng buộc dữ liệu.',
                ),
                SizedBox(height: 12),
                SelectableText(
                  '[\n'
                  '  {\n'
                  '    "collection": "HoaDonBan",\n'
                  '    "filter": {"IdHoaDon": 142},\n'
                  '    "update": {"\$set": {"NgayHen": {"\$date": "2026-12-01T00:00:00Z"}}},\n'
                  '    "note": "Sửa ngày hẹn"\n'
                  '  }\n'
                  ']',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                SizedBox(height: 12),
                Text(
                  'Lệnh chạy lần lượt và dừng ở lỗi đầu tiên; không phải transaction nên lệnh many có thể áp dụng một phần. Kết quả được lưu vào _fix_history. Không sửa được _sync_* hoặc _fix_history.',
                  style: TextStyle(color: Color(0xFF6E7D83)),
                ),
              ],
            ),
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
  }

  Widget _message(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      text,
      style: TextStyle(
        color: error ? const Color(0xFFB5473D) : const Color(0xFF176455),
      ),
    ),
  );

  Widget _stuckPanel() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F7F5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFD9E7E1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.health_and_safety_outlined, color: Color(0xFF176455)),
            SizedBox(width: 8),
            Text(
              'Đơn hàng bị kẹt',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Quét kế hoạch sửa/xóa dở, khóa còn sót và header lệch sổ nợ. '
          'Chỉ sửa dữ liệu, không xóa đơn.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('stuck-scan'),
              onPressed: _stuckBusy ? null : _scanStuck,
              icon: const Icon(Icons.troubleshoot),
              label: const Text('Quét đơn kẹt'),
            ),
            FilledButton.icon(
              key: const ValueKey('stuck-fix'),
              onPressed: !_stuckBusy && (_stuckScan?.hasFixable ?? false)
                  ? _fixStuck
                  : null,
              icon: const Icon(Icons.build_outlined),
              label: const Text('Sửa tất cả'),
            ),
          ],
        ),
        if (_stuckBusy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_stuckError != null) _message(_stuckError!, error: true),
        if (_stuckScan != null) _stuckScanView(_stuckScan!),
        if (_stuckRun != null) _stuckRunView(_stuckRun!),
      ],
    ),
  );

  Widget _stuckScanView(StuckOrderScan scan) {
    final fixable = scan.issues.where((issue) => issue.fixable).length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Đã kiểm tra ${scan.checkedOrders} đơn liên quan · ${scan.pendingPlans} kế hoạch dở · '
            '${scan.staleLocks} khóa sót · ${scan.headerMismatches} header lệch',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          if (scan.issues.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Không phát hiện đơn kẹt.',
                style: TextStyle(color: Color(0xFF176455)),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${scan.issues.length} đơn cần xử lý · $fixable sửa được tự động.',
              ),
            ),
            for (final issue in scan.issues.take(20)) _stuckIssueView(issue),
            if (scan.issues.length > 20)
              Text('… còn ${scan.issues.length - 20} đơn khác.'),
          ],
        ],
      ),
    );
  }

  Widget _stuckIssueView(StuckOrderIssue issue) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '#${issue.orderId} · ${issue.title}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        for (final detail in issue.details)
          Text(
            '• $detail',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
          ),
        for (final action in issue.actions)
          Text(
            '→ $action',
            style: const TextStyle(fontSize: 12, color: Color(0xFF176455)),
          ),
        if (issue.blocker != null)
          Text(
            issue.blocker!,
            style: const TextStyle(fontSize: 12, color: Color(0xFFB26A00)),
          ),
      ],
    ),
  );

  Widget _stuckRunView(StuckOrderRepairRun run) {
    final fixed = run.results.where((result) => result.fixed).length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                run.ok ? Icons.check_circle_outline : Icons.error_outline,
                color: run.ok
                    ? const Color(0xFF176455)
                    : const Color(0xFFB5473D),
              ),
              const SizedBox(width: 8),
              Text(
                'Đã sửa $fixed/${run.results.length} đơn.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final result in run.results)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '#${result.orderId}: ${result.ok ? (result.fixed ? 'Đã sửa' : 'Không cần ghi') : 'Lỗi: ${result.message}'}',
                style: TextStyle(
                  fontSize: 12,
                  color: result.ok
                      ? const Color(0xFF176455)
                      : const Color(0xFFB5473D),
                ),
              ),
            ),
          Text(
            run.scan.issues.isEmpty
                ? 'Không còn đơn kẹt.'
                : 'Còn ${run.scan.issues.length} đơn cần xử lý.',
            style: TextStyle(
              fontSize: 12,
              color: run.scan.issues.isEmpty
                  ? const Color(0xFF176455)
                  : const Color(0xFFB26A00),
            ),
          ),
          if (run.historyError != null)
            Text(
              'Không ghi được lịch sử: ${run.historyError}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB26A00)),
            ),
          if (run.wrote) ...[
            const Text(
              'Dữ liệu đã thay đổi. Bấm Tải lại dữ liệu để các màn hình khác đọc lại.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('stuck-reload'),
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Tải lại dữ liệu'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewView(DatabaseFixPreview preview) => Container(
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F7F8),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kiểm tra: ${preview.steps.length} lệnh',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (preview.warning != null) ...[
          const SizedBox(height: 8),
          Text(
            preview.warning!,
            style: const TextStyle(color: Color(0xFFB5473D)),
          ),
        ],
        const SizedBox(height: 8),
        for (final step in preview.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${step.index} ${_action(step.action)} ${step.collection} · '
                  '${step.action == DatabaseFixAction.insert ? 'thêm 1 bản ghi' : 'khớp ${step.matched} bản ghi'}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (step.note != null)
                  Text(
                    step.note!,
                    style: const TextStyle(color: Color(0xFF6E7D83)),
                  ),
                if (step.warning != null)
                  Text(
                    step.warning!,
                    style: const TextStyle(color: Color(0xFFB26A00)),
                  ),
                if (step.sample != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      step.sample!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF1D3036),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _runView(DatabaseFixRun run) => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: run.ok ? const Color(0xFFEFF8F4) : const Color(0xFFFDF0EE),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              run.ok ? Icons.check_circle_outline : Icons.error_outline,
              color: run.ok ? const Color(0xFF176455) : const Color(0xFFB5473D),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                run.ok
                    ? 'Hoàn tất ${run.steps.length} lệnh trong ${run.duration.inMilliseconds} ms'
                    : 'Dừng ở lệnh #${run.failedStep} · ${run.duration.inMilliseconds} ms',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final step in run.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${step.index} ${_action(step.action)} ${step.collection} · '
                  '${switch (step.action) {
                    DatabaseFixAction.update => 'khớp ${step.matched} · sửa ${step.modified}${step.upserted > 0 ? ' · chèn ${step.upserted}' : ''}',
                    DatabaseFixAction.delete => 'xóa ${step.removed}',
                    DatabaseFixAction.insert => 'chèn ${step.inserted}',
                  }}',
                ),
                if (step.error != null)
                  Text(
                    step.error!,
                    style: const TextStyle(color: Color(0xFFB5473D)),
                  ),
              ],
            ),
          ),
        if (!run.ok)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Các lệnh trước đã ghi; lệnh many có thể đã áp dụng một phần. Hãy kiểm tra lại dữ liệu.',
              style: TextStyle(color: Color(0xFFB26A00)),
            ),
          ),
        if (run.historyError != null)
          Text(
            'Không ghi được lịch sử: ${run.historyError}',
            style: const TextStyle(color: Color(0xFFB26A00)),
          ),
        if (run.wrote) ...[
          const Text(
            'Dữ liệu đã thay đổi. Bấm Tải lại dữ liệu để các màn hình khác đọc lại.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('fix-reload'),
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Tải lại dữ liệu'),
            ),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: FormSection(
      title: null,
      children: [
        _stuckPanel(),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_outlined,
                color: Color(0xFFB26A00),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lệnh ghi trực tiếp vào MongoDB đang dùng. Hãy sao lưu ở tab MongoDB trước khi thực thi; không thể hoàn tác.',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Database: $_target',
                      style: const TextStyle(color: Color(0xFF6E7D83)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('fix-load'),
              onPressed: _busy ? null : _loadFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Nhập từ tệp'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('fix-template'),
              onPressed: _busy ? null : _pickTemplate,
              icon: const Icon(Icons.article_outlined),
              label: const Text('Chèn mẫu'),
            ),
            TextButton.icon(
              key: const ValueKey('fix-help'),
              onPressed: _busy ? null : _showHelp,
              icon: const Icon(Icons.help_outline),
              label: const Text('Định dạng lệnh'),
            ),
            TextButton.icon(
              key: const ValueKey('fix-clear'),
              onPressed: _busy ? null : _clear,
              icon: const Icon(Icons.clear),
              label: const Text('Xóa nội dung'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('fix-script'),
          controller: _script,
          enabled: !_busy,
          minLines: 10,
          maxLines: 18,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Lệnh sửa dữ liệu (JSON)',
            alignLabelWithHint: true,
            hintText:
                '[{"collection": "...", "filter": {...}, "update": {...}}]',
            border: OutlineInputBorder(),
          ),
        ),
        if (_info != null) _message(_info!),
        if (_error != null) _message(_error!, error: true),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('fix-preview'),
                onPressed: _busy ? null : _previewNow,
                icon: const Icon(Icons.search),
                label: const Text('Kiểm tra'),
              ),
              FilledButton.icon(
                key: const ValueKey('fix-execute'),
                onPressed: _busy ? null : _execute,
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Thực thi'),
              ),
            ],
          ),
        ),
        if (_preview != null) _previewView(_preview!),
        if (_run != null) _runView(_run!),
      ],
    ),
  );
}
