import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/settings/database_settings.dart';
import '../../controllers/database_settings_controller.dart';
import '../../models/repositories/database_settings_repository.dart';
import '../../services/native_database_settings_repository.dart';
import '../widgets/form_section.dart';
import 'app_update_panel.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, this.repository, this.initialTab = 0});
  final int initialTab;
  final DatabaseSettingsRepository? repository;
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final DatabaseSettingsController _controller;
  final _mongo = TextEditingController(), _sql = TextEditingController();
  final _cloud = TextEditingController();
  bool _showCloud = false;
  String? _loadedCloud;
  bool _showMongo = false, _showSql = false;
  String? _loadedMongo, _loadedSql;
  @override
  void initState() {
    super.initState();
    _controller = DatabaseSettingsController(
      widget.repository ?? NativeDatabaseSettingsRepository(),
    );
    _mongo.text = _controller.settings.mongoUri;
    _controller.addListener(_changed);
    _controller.load();
  }

  void _changed() {
    if (!mounted) return;
    if (_controller.loaded) {
      if (_loadedCloud != _controller.settings.cloudUri) {
        _cloud.text = _controller.settings.cloudUri;
        _loadedCloud = _cloud.text;
      }
      if (_loadedMongo != _controller.settings.mongoUri) {
        _mongo.text = _controller.settings.mongoUri;
        _loadedMongo = _mongo.text;
      }
      if (_loadedSql != _controller.settings.sqlConnection) {
        _sql.text = _controller.settings.sqlConnection;
        _loadedSql = _sql.text;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _mongo.dispose();
    _sql.dispose();
    _cloud.dispose();
    super.dispose();
  }

  Widget _connection({required bool mongo}) => TextField(
    key: ValueKey(mongo ? 'settings-mongo-uri' : 'settings-sql-connection'),
    controller: mongo ? _mongo : _sql,
    enabled: !_controller.busy,
    obscureText: mongo ? !_showMongo : !_showSql,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: 'Chuỗi kết nối',
      hintText: mongo
          ? 'mongodb://127.0.0.1:27017/XM'
          : 'Server=...;Database=xm;UID=...;PWD=...;Encrypt=yes;TrustServerCertificate=yes;',
      suffixIcon: IconButton(
        tooltip: mongo
            ? (_showMongo ? 'Ẩn chuỗi MongoDB' : 'Hiện chuỗi MongoDB')
            : (_showSql ? 'Ẩn chuỗi SQL Server' : 'Hiện chuỗi SQL Server'),
        onPressed: () => setState(() {
          if (mongo) {
            _showMongo = !_showMongo;
          } else {
            _showSql = !_showSql;
          }
        }),
        icon: Icon(
          (mongo ? _showMongo : _showSql)
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
        ),
      ),
    ),
  );
  Widget _messages(SettingsSection section) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_controller.busyFor(section))
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: LinearProgressIndicator(),
        ),
      if (_controller.errorFor(section) != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _controller.errorFor(section)!,
            style: const TextStyle(color: Color(0xFFB5473D)),
          ),
        ),
      if (_controller.messageFor(section) != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _controller.messageFor(section)!,
            style: const TextStyle(color: Color(0xFF176455)),
          ),
        ),
    ],
  );
  Future<void> _clone() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sao chép database xm'),
        content: const Text(
          'Chỉ sao chép bảng dữ liệu, bỏ qua view và thủ tục. Bản dữ liệu mới sẽ được kiểm tra và chuẩn hóa; dữ liệu MongoDB đang dùng được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bắt đầu sao chép'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) await _controller.clone(_sql.text);
  }

  Widget _mongoPage() {
    final status = _controller.mongo;
    final text = status == null
        ? 'Kiểm tra MongoDB trên máy và kết nối đến database.'
        : status.connected
        ? 'Đã kết nối MongoDB${status.database == null ? '' : ': ${status.database}'}.'
        : status.installed
        ? 'Máy đã cài MongoDB nhưng chưa kết nối được. Kiểm tra dịch vụ MongoDB và chuỗi kết nối.'
        : 'Chưa phát hiện MongoDB trên máy. Vui lòng cài MongoDB Community Server để dùng dữ liệu tại máy này.';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: FormSection(
        title: null,
        children: [
          _messages(SettingsSection.mongo),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                status?.connected == true
                    ? Icons.check_circle_outline
                    : Icons.storage_outlined,
                color: const Color(0xFF176455),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text)),
            ],
          ),
          if (status != null && !status.installed) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _controller.busy
                    ? null
                    : _controller.openInstallation,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Hướng dẫn cài MongoDB'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _connection(mongo: true),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('settings-check-mongo'),
                onPressed: _controller.busy
                    ? null
                    : () => _controller.checkMongo(_mongo.text),
                icon: const Icon(Icons.sync),
                label: const Text('Kiểm tra kết nối'),
              ),
              FilledButton.icon(
                key: const ValueKey('settings-save-mongo'),
                onPressed: _controller.busy
                    ? null
                    : () => _controller.saveMongo(_mongo.text),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu kết nối'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _syncCloud(bool upload) async {
    await _runCloudWork(
      () => _controller.compareCloud(upload: upload),
      'Đang so sánh phiên bản',
    );
    if (!mounted ||
        _controller.errorFor(SettingsSection.cloud) != null ||
        _controller.comparison == null) {
      return;
    }
    final preview = _controller.comparison!;
    String policy = 'abort';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            upload ? 'Đồng bộ dữ liệu lên cloud?' : 'Tải dữ liệu từ cloud về?',
          ),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${upload ? 'Trên máy' : 'Trên cloud'}: ${preview.sourceVersion.label}',
                  ),
                  Text(
                    '${upload ? 'Trên cloud' : 'Trên máy'}: ${preview.targetVersion.label}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Chỉ có ở ${upload ? 'máy' : 'cloud'}: ${preview.sourceOnly} bản ghi',
                  ),
                  Text(
                    'Chỉ có ở ${upload ? 'cloud' : 'máy'}: ${preview.targetOnly} bản ghi',
                  ),
                  Text(
                    'Giống nhau: ${preview.identical} · Khác nội dung cùng khóa: ${preview.conflicts}',
                  ),
                  Text(
                    'Bảng có cấu trúc khác nhau: ${preview.schemaConflicts}',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Cảnh báo: gộp theo khóa bản ghi vào một database mới. Bản ghi chỉ có ở một bên được giữ lại; thao tác xóa không tự truyền sang bên kia. Hãy dừng nhập liệu trên các máy khi thực hiện.',
                  ),
                  if (preview.hasConflicts) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Hai bên có xung đột. Bên được ưu tiên sẽ quyết định toàn bộ nội dung bản ghi trùng khóa và cấu trúc bảng khác nhau. Hãy đối chiếu hóa đơn, công nợ và tồn kho trước khi lựa chọn.',
                    ),
                    DropdownButton<String>(
                      key: const ValueKey('settings-conflict-policy'),
                      isExpanded: true,
                      value: policy,
                      items: [
                        const DropdownMenuItem(
                          value: 'abort',
                          child: Text('Chưa chọn — không ghi đè xung đột'),
                        ),
                        DropdownMenuItem(
                          value: 'source',
                          child: Text(
                            upload
                                ? 'Ưu tiên dữ liệu trên máy'
                                : 'Ưu tiên dữ liệu trên cloud',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'target',
                          child: Text(
                            upload
                                ? 'Ưu tiên dữ liệu trên cloud'
                                : 'Ưu tiên dữ liệu trên máy',
                          ),
                        ),
                      ],
                      onChanged: (value) => update(() => policy = value!),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    upload
                        ? 'Kết quả được lưu thành bản mới trên cả máy và cloud. Hai phía cùng sử dụng dữ liệu gộp đã đối chiếu; các database cũ được giữ lại.'
                        : 'Kết quả được lưu thành bản mới trên cả máy và cloud. Hai phía cùng sử dụng dữ liệu gộp đã đối chiếu; các database cũ được giữ lại.',
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
              onPressed: preview.hasConflicts && policy == 'abort'
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Tiếp tục'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    await _runCloudWork(
      () => _controller.syncCloud(upload: upload, conflictPolicy: policy),
      'Đang gộp dữ liệu',
    );
  }

  Future<void> _runCloudWork(Future<void> Function() work, String title) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: _CloudWorkProgress(controller: _controller),
          ),
        ),
      ),
    );
    try {
      await work();
    } finally {
      if (navigator.mounted) navigator.pop();
    }
  }

  String _syncTime(DateTime? value) => value == null
      ? 'Chưa đồng bộ'
      : DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());

  Widget _cloudCard(String title, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE5EAED)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );

  Widget _versionCard(String title, DatabaseVersion? version, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8F7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF176455)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  const SizedBox(height: 4),
                  Text(
                    version?.label ?? 'Chưa kiểm tra',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (version != null)
                    Text(
                      '${version.collections} bảng · ${version.rows} dòng',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _cloudPage() {
    final settings = _controller.settings;
    final ready =
        !_controller.busy &&
        settings.cloudUri.isNotEmpty &&
        _cloud.text.trim() == settings.cloudUri;
    final matched =
        settings.databaseVersion != null &&
        settings.cloudVersion != null &&
        settings.databaseVersion!.version == settings.cloudVersion!.version &&
        settings.databaseVersion!.revision == settings.cloudVersion!.revision;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _messages(SettingsSection.cloud),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text(
                    'MongoDB Cloud',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  Chip(
                    avatar: Icon(
                      matched
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_outlined,
                      size: 18,
                    ),
                    label: Text(
                      matched
                          ? 'Hai phiên bản khớp nhau'
                          : 'Chưa xác nhận đồng bộ',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _cloudCard(
                'Kết nối cloud',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey('settings-cloud-uri'),
                      controller: _cloud,
                      onChanged: (_) => setState(() {}),
                      enabled: !_controller.busy,
                      obscureText: !_showCloud,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Chuỗi kết nối MongoDB Cloud',
                        hintText:
                            'mongodb+srv://user:password@cluster.mongodb.net/XM',
                        suffixIcon: IconButton(
                          tooltip: _showCloud
                              ? 'Ẩn chuỗi cloud'
                              : 'Hiện chuỗi cloud',
                          onPressed: () =>
                              setState(() => _showCloud = !_showCloud),
                          icon: Icon(
                            _showCloud
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Cho phép IP máy này truy cập và cấp tài khoản quyền đọc/ghi, tạo database bản sao.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('settings-check-cloud'),
                          onPressed: _controller.busy
                              ? null
                              : () => _controller.checkCloud(_cloud.text),
                          icon: const Icon(Icons.wifi_tethering, size: 18),
                          label: const Text('Kiểm tra kết nối'),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey('settings-save-cloud'),
                          onPressed: _controller.busy
                              ? null
                              : () => _controller.checkCloud(
                                  _cloud.text,
                                  save: true,
                                ),
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Lưu kết nối cloud'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _cloudCard(
                'Phiên bản & đồng bộ',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, bounds) {
                        final local = _versionCard(
                          'Dữ liệu trên máy',
                          settings.databaseVersion,
                          Icons.computer_outlined,
                        );
                        final cloud = _versionCard(
                          'Dữ liệu trên cloud',
                          settings.cloudVersion,
                          Icons.cloud_outlined,
                        );
                        return bounds.maxWidth >= 620
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: local),
                                  const SizedBox(width: 12),
                                  Expanded(child: cloud),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  local,
                                  const SizedBox(height: 10),
                                  cloud,
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Đồng bộ thành công gần nhất: ${_syncTime(settings.lastSyncAt)}',
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ứng dụng nhắc khi mở nếu đã 30 ngày chưa đồng bộ. Phiên bản hiển thị là kết quả kiểm tra gần nhất.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('settings-upload-cloud'),
                          onPressed: ready ? () => _syncCloud(true) : null,
                          icon: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 18,
                          ),
                          label: const Text('Đồng bộ lên cloud'),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey('settings-download-cloud'),
                          onPressed: ready ? () => _syncCloud(false) : null,
                          icon: const Icon(
                            Icons.cloud_download_outlined,
                            size: 18,
                          ),
                          label: const Text('Tải dữ liệu từ cloud'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('settings-compare-cloud'),
                          onPressed: ready
                              ? () => _runCloudWork(
                                  () => _controller.compareCloud(upload: true),
                                  'Đang so sánh phiên bản',
                                )
                              : null,
                          icon: const Icon(Icons.compare_arrows, size: 18),
                          label: const Text('So sánh phiên bản'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'So sánh và cảnh báo xung đột trước khi gộp. Sau khi hoàn tất, máy và cloud cùng sử dụng dữ liệu đã đối chiếu; các bản cũ được giữ lại.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _cloudCard(
                'Lịch sử đồng bộ',
                Column(
                  key: const ValueKey('settings-sync-history'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (settings.syncHistory.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Chưa có lịch sử đồng bộ.'),
                      )
                    else ...[
                      const Text(
                        '50 lần thực hiện gần nhất trên máy này',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6E7D83),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final entry in settings.syncHistory)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                entry.success
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                color: entry.success
                                    ? const Color(0xFF176455)
                                    : const Color(0xFFB5473D),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${entry.upload ? 'Đồng bộ lên cloud' : 'Tải dữ liệu từ cloud'} · ${entry.success ? 'Thành công' : 'Thất bại'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _syncTime(entry.at),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6E7D83),
                                      ),
                                    ),
                                    if (entry.success)
                                      Text(
                                        '${entry.version?.label ?? ''} · ${entry.collections} bảng · ${entry.rows} dòng',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sqlPage() {
    final result = _controller.cloneResult;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: FormSection(
        title: null,
        children: [
          _messages(SettingsSection.sql),
          _connection(mongo: false),
          const SizedBox(height: 12),
          const Text(
            r'Xác thực Windows: Server=.\SQLEXPRESS;Database=XM;Trusted_Connection=True;'
            '\nDùng tài khoản Windows đang chạy ứng dụng, không cần UID hoặc PWD.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('settings-check-sql'),
                onPressed: _controller.busy
                    ? null
                    : () => _controller.checkSql(_sql.text),
                icon: const Icon(Icons.sync),
                label: const Text('Kiểm tra kết nối'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('settings-save-sql'),
                onPressed: _controller.busy
                    ? null
                    : () => _controller.checkSql(_sql.text, save: true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu kết nối'),
              ),
              FilledButton.icon(
                key: const ValueKey('settings-clone'),
                onPressed:
                    _controller.busy ||
                        !_controller.loaded ||
                        _controller.mongo?.connected != true
                    ? null
                    : _clone,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Sao chép sang MongoDB'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Bản sao chỉ lấy dữ liệu từ SQL Server và được lưu riêng. Bản MongoDB đang dùng được giữ nguyên.',
          ),
          if (_controller.progressFor(SettingsSection.sql).isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              height: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7F8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView(
                children: [
                  for (final line in _controller.progressFor(
                    SettingsSection.sql,
                  ))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(line),
                    ),
                ],
              ),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 20),
            Text('Database mới: ${result.database}'),
            Text(
              'Đã đối chiếu ${result.rows} dòng, dọn ${result.orphans} dòng thiếu bản ghi cha và gộp ${result.purchases} đơn mua.',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('settings-use-clone'),
                onPressed: _controller.busy ? null : _controller.useClone,
                icon: const Icon(Icons.check),
                label: const Text('Sử dụng bản sao này'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    initialIndex: widget.initialTab,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EAED)),
      ),
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'MongoDB'),
              Tab(text: 'SQL Server'),
              Tab(text: 'MongoDB Cloud'),
              Tab(text: 'Phiên bản'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _mongoPage(),
                _sqlPage(),
                _cloudPage(),
                const AppUpdatePanel(),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CloudWorkProgress extends StatefulWidget {
  const _CloudWorkProgress({required this.controller});
  final DatabaseSettingsController controller;
  @override
  State<_CloudWorkProgress> createState() => _CloudWorkProgressState();
}

class _CloudWorkProgressState extends State<_CloudWorkProgress> {
  final _clock = Stopwatch()..start();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final lines = widget.controller.progressFor(SettingsSection.cloud);
      final elapsed = _clock.elapsed;
      return SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(lines.isEmpty ? 'Đang kết nối…' : lines.last),
            const SizedBox(height: 10),
            Text(
              'Đã chạy ${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
            ),
          ],
        ),
      );
    },
  );
}
