import 'package:flutter/foundation.dart';
import '../models/pawn/pawn_models.dart';
import '../models/repositories/pawn_repository.dart';

class PawnDetailsController extends ChangeNotifier {
  PawnDetailsController(this.repository, this.id);
  final PawnRepository repository;
  final int id;
  PawnDetails? data;
  String? error;
  bool loading = false, _disposed = false;
  Future<void> load() async {
    if (_disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.details(id);
      if (!_disposed) data = result;
    } on PawnException catch (e) {
      if (!_disposed) error = e.message;
    } catch (_) {
      if (!_disposed) {
        error = 'Chưa tải được chi tiết cầm đồ. Vui lòng thử lại.';
      }
    }
    if (!_disposed) {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
