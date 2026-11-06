import 'package:flutter/foundation.dart';
import '../models/directory/directory_models.dart';
import '../models/repositories/directory_repository.dart';

class DirectoryController extends ChangeNotifier {
  DirectoryController(this.repository);
  final DirectoryRepository repository;
  final _entries = <DirectoryKind, Map<String, DirectoryEntry>>{};
  final _loading = <DirectoryKind, Future<void>>{};
  final _loaded = <DirectoryKind>{};
  final _errors = <DirectoryKind, String>{};
  bool _disposed = false;
  int _revision = 0;
  String? errorFor(DirectoryKind kind) => _errors[kind];
  Future<void> ensureLoaded(DirectoryKind kind) {
    if (_loaded.contains(kind) || _disposed) return Future.value();
    return _loading[kind] ??= _load(kind).whenComplete(() {
      _loading.remove(kind);
    });
  }

  Future<void> _load(DirectoryKind kind) async {
    try {
      final revision = _revision;
      final entries = await repository.fetch(kind);
      if (!_disposed && revision != _revision) {
        await _load(kind);
        return;
      }
      if (_disposed) return;
      _entries[kind] = {for (final e in entries) e.id: e};
      _loaded.add(kind);
      _errors.remove(kind);
    } catch (_) {
      if (!_disposed) {
        _errors[kind] = 'Không tải được danh mục. Nhập lại để thử kết nối.';
      }
    }
    if (!_disposed) notifyListeners();
  }

  Iterable<DirectoryEntry> search(DirectoryKind kind, String query) =>
      (_entries[kind]?.values ?? const <DirectoryEntry>[])
          .where((e) => e.matches(query))
          .take(15);
  Future<DirectoryEntry> create(DirectoryEntryDraft draft) async {
    final entry = await repository.create(draft);
    _revision++;
    if (!_disposed) {
      (_entries[entry.kind] ??= {})[entry.id] = entry;
      notifyListeners();
    }
    return entry;
  }

  Future<DirectoryEntry> update(
    DirectoryEntry entry,
    DirectoryEntryDraft draft,
  ) async {
    final saved = await repository.update(entry.id, draft);
    _revision++;
    (_entries[saved.kind] ??= {})[saved.id] = saved;
    if (!_disposed) notifyListeners();
    return saved;
  }

  Future<void> delete(DirectoryEntry entry) async {
    await repository.delete(entry);
    _revision++;
    _entries[entry.kind]?.remove(entry.id);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class DirectoryEditController extends ChangeNotifier {
  DirectoryEditController(
    this.directory,
    DirectoryKind kind,
    String initialName, {
    this.existing,
  }) : draft = DirectoryEntryDraft(kind, name: existing?.name ?? initialName)
         ..phone = existing?.phone ?? ''
         ..address = existing?.address ?? ''
         ..taxCode = existing?.taxCode ?? ''
         ..representative = existing?.representative ?? ''
         ..plate = existing?.plate ?? ''
         ..notes = existing?.notes ?? '';
  final DirectoryEntry? existing;
  final DirectoryController directory;
  final DirectoryEntryDraft draft;
  bool saving = false, _disposed = false;
  String? error;
  Future<DirectoryEntry?> save() async {
    if (saving || _disposed) return null;
    if (draft.name.trim().isEmpty) {
      error = 'Vui lòng nhập tên.';
      notifyListeners();
      return null;
    }
    saving = true;
    error = null;
    notifyListeners();
    try {
      final entry = existing == null
          ? await directory.create(draft)
          : await directory.update(existing!, draft);
      if (_disposed) return null;
      saving = false;
      notifyListeners();
      return entry;
    } catch (_) {
      if (_disposed) return null;
      saving = false;
      error = 'Không lưu được dữ liệu. Vui lòng kiểm tra kết nối và thử lại.';
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
