enum RecordKind {
  order,
  batch,
  pawn,
  funding,
  openingDebt,
  cash,
  vehicleProduct,
  partProduct,
}

class RecordEditData {
  const RecordEditData(this.header, this.lines, this.payments);
  final Map<String, dynamic> header;
  final List<Map<String, dynamic>> lines, payments;
}

class RecordChangeException implements Exception {
  const RecordChangeException(this.message, {this.uncertain = false});
  final bool uncertain;
  final String message;
  @override
  String toString() => message;
}

abstract class RecordMaintenance {
  Future<List<Map<String, dynamic>>> pending();
  Future<void> ensureReadable(RecordKind kind, int id);
  Future<void> close() async {}
  Future<List<Map<String, dynamic>>> suggestions(
    String collection,
    String search,
  );
  Future<void> recover(RecordKind kind, int id);
  Future<RecordEditData> load(RecordKind kind, int id);
  Future<void> save(
    RecordKind kind,
    int id,
    Map<String, dynamic> fields,
    List<Map<String, dynamic>> lines, {
    required String requestId,
  });
  Future<void> removeLine(
    RecordKind kind,
    int id,
    dynamic lineId, {
    required String requestId,
  }) async => throw UnimplementedError();
  Future<void> deleteCost(
    bool vehicle,
    int productId,
    Map<String, dynamic> cost, {
    required String requestId,
  }) async => throw UnimplementedError();
  Future<void> delete(RecordKind kind, int id, {required String requestId});
  Future<void> payment(
    RecordKind kind,
    int parentId,
    dynamic paymentId,
    Map<String, dynamic>? fields, {
    required String requestId,
    DateTime? interestStart,
    DateTime? nextAppointment,
  });
}
