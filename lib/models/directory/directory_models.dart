enum DirectoryKind {
  partner('Đối tác / nhà cung cấp'),
  carrier('Vận chuyển');

  const DirectoryKind(this.label);
  final String label;
}

class DirectoryEntry {
  const DirectoryEntry({
    required this.id,
    required this.kind,
    required this.name,
    this.phone = '',
    this.address = '',
    this.taxCode = '',
    this.representative = '',
    this.plate = '',
    this.notes = '',
  });
  final String id, name, phone, address, taxCode, representative, plate, notes;
  final DirectoryKind kind;
  String get subtitle {
    final parts = [
      phone,
      kind == DirectoryKind.carrier ? plate : address,
    ].where((v) => v.trim().isNotEmpty).toList();
    return parts.isNotEmpty
        ? parts.join(' · ')
        : '#${id.length > 6 ? id.substring(id.length - 6) : id}';
  }

  bool matches(String query) => [
    name,
    phone,
    address,
    taxCode,
    representative,
    plate,
  ].any((value) => value.toLowerCase().contains(query.trim().toLowerCase()));
}

class DirectoryEntryDraft {
  DirectoryEntryDraft(this.kind, {this.name = ''});
  final DirectoryKind kind;
  String name,
      phone = '',
      address = '',
      taxCode = '',
      representative = '',
      plate = '',
      notes = '';
}
