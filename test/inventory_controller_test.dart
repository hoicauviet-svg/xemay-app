import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/inventory_controller.dart';
import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'support/fake_inventory_repository.dart';

class DelayedRepository extends FakeInventoryRepository {
  final pending = <Completer<InventoryPage>>[];
  @override
  Future<InventoryPage> fetch(
    InventorySection view, {
    String search = '',
    String condition = '',
    String availability = 'all',
    int page = 0,
    int pageSize = 30,
  }) {
    final completer = Completer<InventoryPage>();
    pending.add(completer);
    return completer.future;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('A late response cannot replace the newly selected section', () async {
    final repo = DelayedRepository();
    final controller = InventoryController(repo);
    addTearDown(controller.dispose);
    final first = controller.load();
    await flush();
    controller.selectSection(InventorySection.vehicles);
    await flush();
    expect(repo.pending.length, 2);
    repo.pending[1].complete(
      const InventoryPage([
        {'IdXe': 7},
      ], 1),
    );
    await flush();
    repo.pending[0].complete(
      const InventoryPage([
        {'IdSanPham': 1},
      ], 1),
    );
    await first;
    expect(controller.section, InventorySection.vehicles);
    expect(controller.data!.rows.single['IdXe'], 7);
    expect(controller.loading, isFalse);
  });

  test(
    'Pagination cannot skip pages while loading or move before page zero',
    () async {
      final repo = FakeInventoryRepository();
      final controller = InventoryController(repo);
      addTearDown(controller.dispose);
      await controller.load();
      controller.previousPage();
      expect(controller.page, 0);
      controller.nextPage();
      controller.nextPage();
      await flush();
      expect(controller.page, 1);
      expect(repo.lastPage, 1);
      expect(controller.hasNextPage, isFalse);
      controller.previousPage();
      await flush();
      expect(controller.page, 0);
    },
  );

  testWidgets('Disposal cancels pending search and closes the repository', (
    tester,
  ) async {
    final repo = FakeInventoryRepository();
    final controller = InventoryController(repo);
    controller.searchChanged('không được truy vấn sau khi đóng');
    controller.dispose();
    await tester.pump(const Duration(milliseconds: 350));
    expect(repo.lastSearch, isEmpty);
    expect(repo.closed, isTrue);
  });
}
