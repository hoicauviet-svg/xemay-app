import 'dart:io';

/// Opens an HTTPS link with the operating system's default browser.
Future<void> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FormatException('Liên kết không hợp lệ.');
  }
  if (Platform.isWindows) {
    final result = await Process.run('cmd', ['/c', 'start', '', url]);
    if (result.exitCode != 0) {
      throw StateError('Không mở được liên kết.');
    }
    return;
  }
  final command = Platform.isMacOS ? 'open' : 'xdg-open';
  final result = await Process.run(command, [url]);
  if (result.exitCode != 0) {
    throw StateError('Không mở được liên kết.');
  }
}
