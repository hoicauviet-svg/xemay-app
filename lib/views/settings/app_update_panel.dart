import 'dart:io';

import 'package:flutter/material.dart';

import '../../controllers/app_update_controller.dart';
import '../../core/app_version.dart';
import '../widgets/form_section.dart';

class AppUpdatePanel extends StatefulWidget {
  const AppUpdatePanel({super.key, this.controller});
  final AppUpdateController? controller;

  @override
  State<AppUpdatePanel> createState() => _AppUpdatePanelState();
}

class _AppUpdatePanelState extends State<AppUpdatePanel> {
  late final AppUpdateController _controller;
  late final bool _ownsController;
  final _feed = TextEditingController();
  String? _loadedFeed;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AppUpdateController();
    _controller.addListener(_changed);
    _feed.text = _controller.feedUrl;
    _controller.load().then((_) {
      if (!mounted) return;
      if (_loadedFeed != _controller.feedUrl) {
        _feed.text = _controller.feedUrl;
        _loadedFeed = _feed.text;
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (_ownsController) _controller.dispose();
    _feed.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    await _controller.install();
    if (_controller.phase == UpdatePhase.ready && Platform.isWindows) exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final remote = _controller.remote;
    final available =
        _controller.phase == UpdatePhase.available ||
        _controller.phase == UpdatePhase.downloading ||
        _controller.phase == UpdatePhase.ready;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: FormSection(
        title: null,
        children: [
          Text('Phiên bản hiện tại: ${AppVersion.label}'),
          const SizedBox(height: 8),
          const Text(
            'Ứng dụng tự kiểm tra khi mở nếu đã lưu địa chỉ tệp phiên bản. Bản mới chỉ được cài sau khi xác nhận.',
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('settings-update-feed'),
            controller: _feed,
            enabled: !_controller.busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Địa chỉ tệp phiên bản',
              hintText: 'https://may-chu/xemay/latest.json',
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('settings-save-update'),
                onPressed: _controller.busy
                    ? null
                    : () => _controller.saveFeed(_feed.text),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu địa chỉ'),
              ),
              FilledButton.icon(
                key: const ValueKey('settings-check-update'),
                onPressed: _controller.busy ? null : _controller.check,
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Kiểm tra cập nhật'),
              ),
            ],
          ),
          if (_controller.busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _controller.progress),
          ],
          if (_controller.message != null) ...[
            const SizedBox(height: 16),
            Text(
              _controller.message!,
              style: TextStyle(
                color: _controller.phase == UpdatePhase.error
                    ? const Color(0xFFB5473D)
                    : const Color(0xFF176455),
              ),
            ),
          ],
          if (available && remote != null) ...[
            const SizedBox(height: 16),
            Text('Bản mới: ${remote.label}'),
            if (remote.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(remote.notes),
            ],
            const SizedBox(height: 16),
            if (Platform.isWindows)
              FilledButton.icon(
                key: const ValueKey('settings-install-update'),
                onPressed: _controller.busy ? null : _install,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Tải và cài đặt'),
              )
            else
              const Text('Tệp cài đặt chỉ chạy trên Windows.'),
          ],
        ],
      ),
    );
  }
}

Future<void> checkForUpdateOnLaunch(BuildContext context) async {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return;
  final controller = AppUpdateController();
  try {
    await controller.load();
    if (controller.feedUrl.trim().isEmpty) return;
    await controller.check();
    if (!context.mounted || controller.phase != UpdatePhase.available) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _UpdateDialog(controller: controller),
    );
  } catch (_) {
    // Opening the shop app must not depend on the update server.
  } finally {
    controller.dispose();
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.controller});
  final AppUpdateController controller;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _install() async {
    await widget.controller.install();
    if (!mounted) return;
    if (widget.controller.phase == UpdatePhase.ready && Platform.isWindows) {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final release = controller.remote;
    return AlertDialog(
      title: const Text('Có phiên bản mới'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            release == null
                ? 'Đã có bản cài mới.'
                : 'Phiên bản ${release.label} sẵn sàng để cài. Ứng dụng sẽ đóng trong lúc cài.',
          ),
          if (release != null && release.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(release.notes),
          ],
          if (controller.message != null &&
              controller.phase == UpdatePhase.error) ...[
            const SizedBox(height: 12),
            Text(
              controller.message!,
              style: const TextStyle(color: Color(0xFFB5473D)),
            ),
          ],
          if (controller.busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: controller.progress),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: controller.busy ? null : () => Navigator.pop(context),
          child: const Text('Để sau'),
        ),
        FilledButton(
          onPressed: controller.busy || !Platform.isWindows ? null : _install,
          child: const Text('Cài đặt'),
        ),
      ],
    );
  }
}
