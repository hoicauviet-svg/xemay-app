class ChangeHistoryEntry {
  const ChangeHistoryEntry(this.raw);
  final Map<String, dynamic> raw;

  dynamic get parentId => raw['ParentId'];
  String get requestId => '${raw['RequestId'] ?? ''}';
  DateTime? get at => raw['At'] is DateTime ? raw['At'] as DateTime : null;
  String get action => '${raw['Action'] ?? ''}';
  String get kind => '${raw['Kind'] ?? ''}';
  String get source => '${raw['Source'] ?? ''}';
  String get summary => '${raw['Summary'] ?? ''}';
  String get machine => '${raw['Machine'] ?? ''}';
  String get platform => '${raw['Platform'] ?? ''}';
  String get appVersion => '${raw['AppVersion'] ?? ''}';
  Map<String, dynamic>? get before => raw['Before'] is Map
      ? Map<String, dynamic>.from(raw['Before'] as Map)
      : null;
  Map<String, dynamic>? get after => raw['After'] is Map
      ? Map<String, dynamic>.from(raw['After'] as Map)
      : null;
  List<Map<String, dynamic>> get changes => [
    for (final value in raw['Changes'] as List? ?? const [])
      if (value is Map) Map<String, dynamic>.from(value),
  ];
}
