abstract class ChangeHistoryRepository {
  Future<List<Map<String, dynamic>>> fetch({
    String search = '',
    int limit = 100,
  });
  Future<void> close();
}
