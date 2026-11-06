class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
}

class AppRelease {
  const AppRelease({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
    this.notes = '',
    this.url = '',
    this.sha256 = '',
  });

  final int major;
  final int minor;
  final int patch;
  final int build;
  final String notes;
  final String url;
  final String sha256;

  String get label => '$major.$minor.$patch+$build';

  int compareTo(AppRelease other) {
    final parts = [major, minor, patch, build];
    final otherParts = [other.major, other.minor, other.patch, other.build];
    for (var i = 0; i < parts.length; i++) {
      final diff = parts[i].compareTo(otherParts[i]);
      if (diff != 0) return diff;
    }
    return 0;
  }

  bool isNewerThan(AppRelease other) => compareTo(other) > 0;

  static final _version = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  factory AppRelease.parse({
    required String version,
    required int build,
    String notes = '',
    String url = '',
    String sha256 = '',
  }) {
    final match = _version.firstMatch(version.trim());
    if (match == null || build < 0) {
      throw const UpdateException('Số phiên bản không hợp lệ.');
    }
    final digest = sha256.trim().toLowerCase();
    if (digest.isNotEmpty && !_sha256.hasMatch(digest)) {
      throw const UpdateException('Mã kiểm tra của bản cài không hợp lệ.');
    }
    if (url.trim().isNotEmpty) validateHttpUrl(url);
    return AppRelease(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      build: build,
      notes: notes.length > 2000 ? notes.substring(0, 2000) : notes,
      url: url.trim(),
      sha256: digest,
    );
  }

  factory AppRelease.fromManifest(Map<String, dynamic> json) {
    final version = json['version'];
    final build = json['build'];
    if (version is! String || build is! num) {
      throw const UpdateException(
        'Tệp phiên bản thiếu số phiên bản hoặc số bản dựng.',
      );
    }
    return AppRelease.parse(
      version: version,
      build: build.toInt(),
      notes: json['notes'] is String ? json['notes'] as String : '',
      url: json['url'] is String ? json['url'] as String : '',
      sha256: json['sha256'] is String ? json['sha256'] as String : '',
    );
  }

  void validateInstaller() {
    validateHttpUrl(url);
    if (!_sha256.hasMatch(sha256)) {
      throw const UpdateException('Mã kiểm tra của bản cài không hợp lệ.');
    }
  }
}

void validateHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    throw const UpdateException(
      'Địa chỉ cập nhật phải là liên kết http hoặc https.',
    );
  }
}
