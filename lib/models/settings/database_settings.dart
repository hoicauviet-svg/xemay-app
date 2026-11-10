class DatabaseSettings {
  const DatabaseSettings({
    required this.mongoUri,
    this.sqlConnection = '',
    this.cloudUri = '',
  });
  final String mongoUri, sqlConnection, cloudUri;
  Map<String, dynamic> toJson() => {
    'mongoUri': mongoUri,
    'sqlConnection': sqlConnection,
    'cloudUri': cloudUri,
  };
}

class MongoInstallationStatus {
  const MongoInstallationStatus({
    required this.installed,
    required this.connected,
    this.database,
  });
  final bool installed, connected;
  final String? database;
}

class DatabaseCloneResult {
  const DatabaseCloneResult({
    required this.mongoUri,
    required this.database,
    required this.rows,
    required this.orphans,
    required this.purchases,
  });
  final String mongoUri, database;
  final int rows, orphans, purchases;
}

class DatabaseSettingsException implements Exception {
  const DatabaseSettingsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CloudSyncResult {
  const CloudSyncResult({
    required this.mongoUri,
    required this.database,
    required this.rows,
    required this.collections,
  });
  final String mongoUri, database;
  final int rows, collections;
}
