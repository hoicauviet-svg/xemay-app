import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/updates/app_release.dart';

abstract class AppUpdateClient {
  Future<String> fetchFeed(Uri url);
  Future<void> download(
    Uri url,
    File destination, {
    void Function(int received, int? total)? onProgress,
  });
}

class HttpAppUpdateClient implements AppUpdateClient {
  HttpAppUpdateClient({HttpClient? this.client});
  final HttpClient? client;
  static const _feedLimit = 1024 * 1024;
  static const _installerLimit = 300 * 1024 * 1024;

  HttpClient _open() {
    final http = client ?? HttpClient();
    http.connectionTimeout = const Duration(seconds: 20);
    return http;
  }

  Future<HttpClientResponse> _get(HttpClient client, Uri url) async {
    validateHttpUrl(url.toString());
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw UpdateException(
          'Máy chủ cập nhật trả về mã ${response.statusCode}.',
        );
      }
      return response;
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException('Hết thời gian chờ máy chủ cập nhật.');
    } catch (_) {
      throw const UpdateException('Chưa kết nối được máy chủ cập nhật.');
    }
  }

  Future<List<int>> _read(
    HttpClientResponse response, {
    required int limit,
    void Function(int received, int? total)? onProgress,
  }) async {
    final bytes = <int>[];
    final total = response.contentLength < 0 ? null : response.contentLength;
    await for (final chunk in response.timeout(const Duration(minutes: 15))) {
      if (bytes.length + chunk.length > limit) {
        throw const UpdateException('Tệp tải về lớn hơn giới hạn cho phép.');
      }
      bytes.addAll(chunk);
      onProgress?.call(bytes.length, total);
    }
    return bytes;
  }

  @override
  Future<String> fetchFeed(Uri url) async {
    final http = _open();
    try {
      final response = await _get(http, url);
      final bytes = await _read(response, limit: _feedLimit);
      return utf8.decode(bytes);
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  @override
  Future<void> download(
    Uri url,
    File destination, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final http = _open();
    try {
      final response = await _get(http, url);
      final bytes = await _read(
        response,
        limit: _installerLimit,
        onProgress: onProgress,
      );
      final temporary = File('${destination.path}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    } finally {
      if (client == null) http.close(force: true);
    }
  }
}
