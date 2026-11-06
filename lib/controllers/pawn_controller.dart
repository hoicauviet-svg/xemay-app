import 'package:flutter/foundation.dart';
import '../models/pawn/pawn_models.dart';
import '../models/repositories/pawn_repository.dart';

class PawnController extends ChangeNotifier {
  PawnController(this.repository, {this.customerId});
  final int? customerId;
  final PawnRepository repository;
  PawnPage? data;
  bool loading = false, _disposed = false;
  String? error;
  String search = '', status = 'active';
  static const statusLabels = {
    'active': 'Đang cầm',
    'closed': 'Đã chuộc / tất toán',
    'all': 'Tất cả',
  };
  void setStatus(String value) {
    if (!statusLabels.containsKey(value)) return;
    status = value;
    page = 0;
    load();
  }

  int page = 0, _request = 0;
  int get pageCount => ((data?.total ?? 0) / 30).ceil().clamp(1, 1000000);
  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.fetch(
        search: search,
        page: page,
        customerId: customerId,
        status: status,
      );
      if (_disposed || request != _request) return;
      data = result;
    } catch (_) {
      if (_disposed || request != _request) return;
      error = 'Chưa tải được danh sách cầm đồ. Vui lòng thử lại.';
    }
    loading = false;
    notifyListeners();
  }

  void changeSearch(String value) {
    search = value;
    page = 0;
    load();
  }

  void goToPage(int value) {
    if (loading || value < 0 || value >= pageCount) return;
    page = value;
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
