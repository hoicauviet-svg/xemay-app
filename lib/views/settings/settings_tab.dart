import 'package:flutter/material.dart';
import '../../controllers/database_settings_controller.dart';
import '../../models/repositories/database_settings_repository.dart';
import '../../services/native_database_settings_repository.dart';
import '../widgets/form_section.dart';
import 'app_update_panel.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, this.repository});
  final DatabaseSettingsRepository? repository;
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final DatabaseSettingsController _controller;
  final _mongo = TextEditingController(), _sql = TextEditingController();
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
  Widget _messages() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_controller.busy)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: LinearProgressIndicator(),
        ),
      if (_controller.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _controller.error!,
            style: const TextStyle(color: Color(0xFFB5473D)),
          ),
        ),
      if (_controller.message != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _controller.message!,
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
          _messages(),
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

  Widget _sqlPage() {
    final result = _controller.cloneResult;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: FormSection(
        title: null,
        children: [
          _messages(),
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
          if (_controller.progress.isNotEmpty) ...[
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
                  for (final line in _controller.progress)
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
    length: 3,
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
              Tab(text: 'Phiên bản'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_mongoPage(), _sqlPage(), const AppUpdatePanel()],
            ),
          ),
        ],
      ),
    ),
  );
}
