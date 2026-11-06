import 'dart:async';

abstract final class DatabaseConfig {
  static const defaultMongoUri = String.fromEnvironment(
    'MONGO_URI',
    defaultValue:
        'mongodb://127.0.0.1:27017/XM?connectTimeoutMS=5000&socketTimeoutMS=10000',
  );
  static String _mongoUri = defaultMongoUri;
  static String get mongoUri => _mongoUri;
  static String _configuredMongoUri = defaultMongoUri;
  static String get configuredMongoUri => _configuredMongoUri;
  static int revision = 0;
  static bool startupReadFailed = false;
  static final _changes = StreamController<int>.broadcast(sync: true);
  static Stream<int> get changes => _changes.stream;
  static void useMongo(String uri, {String? runtimeUri}) {
    final next = runtimeUri ?? uri;
    _configuredMongoUri = uri;
    if (_mongoUri == next) return;
    _mongoUri = next;
    _changes.add(++revision);
  }
}
