import 'package:mongo_dart/mongo_dart.dart';
import '../models/settings/database_settings.dart';

abstract final class MongoConnectionUri {
  static void validate(String uri) {
    try {
      if (!uri.startsWith('mongodb://') && !uri.startsWith('mongodb+srv://')) {
        throw const FormatException();
      }
      final nodes = uri.startsWith('mongodb+srv://') ? [uri] : Db(uri).uriList;
      for (final node in nodes) {
        final value = Uri.parse(node);
        if (value.host.isEmpty || value.fragment.isNotEmpty) {
          throw const FormatException();
        }
      }
    } catch (_) {
      throw const DatabaseSettingsException(
        'Nhập chuỗi kết nối MongoDB hợp lệ.',
      );
    }
  }

  static String _authority(String uri) {
    final start = uri.indexOf('://') + 3;
    final positions = [
      uri.indexOf('/', start),
      uri.indexOf('?', start),
      uri.indexOf('#', start),
    ].where((i) => i >= 0).toList()..sort();
    return uri.substring(
      start,
      positions.isEmpty ? uri.length : positions.first,
    );
  }

  static String standard(List<String> nodes) {
    final first = nodes.first;
    final authority = _authority(first);
    final split = authority.lastIndexOf('@');
    final credentials = split < 0 ? '' : authority.substring(0, split + 1);
    final hosts = nodes
        .map((node) {
          final auth = _authority(node);
          return auth.substring(auth.lastIndexOf('@') + 1);
        })
        .join(',');
    var suffix = first.substring(first.indexOf('://') + 3 + authority.length);
    if (suffix.isEmpty || suffix.startsWith('?')) {
      suffix = '/XM$suffix';
    } else if (suffix == '/' || suffix.startsWith('/?')) {
      suffix = '/XM${suffix.substring(1)}';
    }
    return 'mongodb://$credentials$hosts$suffix';
  }

  static Future<String> resolve(String uri) async {
    validate(uri);
    final db = await Db.create(uri);
    return standard(db.uriList);
  }
}
