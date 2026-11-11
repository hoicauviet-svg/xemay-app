class DatabaseSettings {
  const DatabaseSettings({
    required this.mongoUri,
    this.sqlConnection = '',
    this.cloudUri = '',
    this.databaseVersion,
    this.cloudVersion,
    this.lastSyncAt,
    this.syncReminderStartedAt,
    this.backupDirectory = '',
    this.lastBackupAt,
    this.syncHistory = const [],
  });
  final String mongoUri, sqlConnection, cloudUri, backupDirectory;
  final DatabaseVersion? databaseVersion, cloudVersion;
  final DateTime? lastSyncAt, syncReminderStartedAt, lastBackupAt;
  final List<SyncHistoryEntry> syncHistory;
  DatabaseSettings copyWith({
    String? mongoUri,
    String? sqlConnection,
    String? cloudUri,
    DatabaseVersion? databaseVersion,
    DatabaseVersion? cloudVersion,
    DateTime? lastSyncAt,
    DateTime? syncReminderStartedAt,
    String? backupDirectory,
    DateTime? lastBackupAt,
    List<SyncHistoryEntry>? syncHistory,
  }) => DatabaseSettings(
    mongoUri: mongoUri ?? this.mongoUri,
    sqlConnection: sqlConnection ?? this.sqlConnection,
    cloudUri: cloudUri ?? this.cloudUri,
    lastSyncAt:
        lastSyncAt ??
        ((mongoUri != null && mongoUri != this.mongoUri) ||
                (cloudUri != null && cloudUri != this.cloudUri)
            ? null
            : this.lastSyncAt),
    syncReminderStartedAt: syncReminderStartedAt ?? this.syncReminderStartedAt,
    backupDirectory: backupDirectory ?? this.backupDirectory,
    lastBackupAt: lastBackupAt ?? this.lastBackupAt,
    syncHistory: syncHistory ?? this.syncHistory,
    databaseVersion:
        databaseVersion ??
        (mongoUri != null && mongoUri != this.mongoUri
            ? null
            : this.databaseVersion),
    cloudVersion:
        cloudVersion ??
        (cloudUri != null && cloudUri != this.cloudUri
            ? null
            : this.cloudVersion),
  );
  Map<String, dynamic> toJson() => {
    'mongoUri': mongoUri,
    'sqlConnection': sqlConnection,
    'cloudUri': cloudUri,
    'databaseVersion': databaseVersion?.toJson(),
    'cloudVersion': cloudVersion?.toJson(),
    'lastSyncAt': lastSyncAt?.toUtc().toIso8601String(),
    'syncReminderStartedAt': syncReminderStartedAt?.toUtc().toIso8601String(),
    'backupDirectory': backupDirectory,
    'lastBackupAt': lastBackupAt?.toUtc().toIso8601String(),
    'syncHistory': syncHistory.map((entry) => entry.toJson()).toList(),
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

class MongoBackupResult {
  const MongoBackupResult({
    required this.database,
    required this.collections,
    required this.rows,
  });
  final String database;
  final int collections, rows;
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
    this.version,
    this.sourceMongoUri,
  });
  final String? sourceMongoUri;
  final DatabaseVersion? version;
  final String mongoUri, database;
  final int rows, collections;
}

class DatabaseVersion {
  const DatabaseVersion({
    required this.version,
    required this.revision,
    required this.observedAt,
    required this.rows,
    required this.collections,
  });
  final String version, observedAt;
  final int revision, rows, collections;
  String get label =>
      'v$revision · ${version.substring(0, version.length < 12 ? version.length : 12)}';
  factory DatabaseVersion.fromJson(Map<String, dynamic> json) =>
      DatabaseVersion(
        version: json['version'] as String,
        revision: (json['revision'] as num).toInt(),
        observedAt: json['observedAt'] as String,
        rows: (json['rows'] as num).toInt(),
        collections: (json['collections'] as num).toInt(),
      );
  Map<String, dynamic> toJson() => {
    'version': version,
    'revision': revision,
    'observedAt': observedAt,
    'rows': rows,
    'collections': collections,
  };
}

class CloudComparison {
  const CloudComparison({
    required this.sourceVersion,
    required this.targetVersion,
    required this.sourceOnly,
    required this.targetOnly,
    required this.conflicts,
    required this.schemaConflicts,
    required this.identical,
  });
  final DatabaseVersion sourceVersion, targetVersion;
  final int sourceOnly, targetOnly, conflicts, schemaConflicts, identical;
  bool get hasConflicts => conflicts > 0 || schemaConflicts > 0;
  factory CloudComparison.fromJson(Map<String, dynamic> json) =>
      CloudComparison(
        sourceVersion: DatabaseVersion.fromJson(
          Map<String, dynamic>.from(json['sourceVersion'] as Map),
        ),
        targetVersion: DatabaseVersion.fromJson(
          Map<String, dynamic>.from(json['targetVersion'] as Map),
        ),
        sourceOnly: (json['sourceOnly'] as num).toInt(),
        targetOnly: (json['targetOnly'] as num).toInt(),
        conflicts: (json['conflicts'] as num).toInt(),
        schemaConflicts: (json['schemaConflicts'] as num).toInt(),
        identical: (json['identical'] as num).toInt(),
      );
}

class SyncHistoryEntry {
  const SyncHistoryEntry({
    required this.at,
    required this.upload,
    required this.success,
    this.version,
    this.rows = 0,
    this.collections = 0,
    this.conflictPolicy = 'abort',
  });
  final DateTime at;
  final bool upload, success;
  final DatabaseVersion? version;
  final int rows, collections;
  final String conflictPolicy;
  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'upload': upload,
    'success': success,
    'version': version?.toJson(),
    'rows': rows,
    'collections': collections,
    'conflictPolicy': conflictPolicy,
  };
  factory SyncHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SyncHistoryEntry(
        at: DateTime.parse(json['at'] as String),
        upload: json['upload'] == true,
        success: json['success'] == true,
        version: json['version'] is Map
            ? DatabaseVersion.fromJson(
                Map<String, dynamic>.from(json['version'] as Map),
              )
            : null,
        rows: (json['rows'] as num?)?.toInt() ?? 0,
        collections: (json['collections'] as num?)?.toInt() ?? 0,
        conflictPolicy: json['conflictPolicy'] as String? ?? 'abort',
      );
}
