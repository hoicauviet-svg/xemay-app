import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/goods_receipt_controller.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'support/fake_directory_repository.dart';

void prepareBatch(
  GoodsReceiptController controller, {
  required String quantity,
  required String total,
}) {
  controller.updateBatch((batch) {
    batch.quantity = quantity;
    batch.totalAmount = total;
    batch.deliveredBy = 'Người giao thử';
    batch.origin = 'Nhà cung cấp thử';
    batch.partnerId = 'partner-test';
    batch.carrierId = 'carrier-test';
  });
  expect(controller.confirmBatch(), isNull);
}

void main() {
  test('Single receipts default to full payment until explicitly edited', () {
    for (final type in ReceiptProductType.values) {
      final controller = GoodsReceiptController(type);
      addTearDown(controller.dispose);
      controller.updateLine(controller.lines.single, (line) {
        line.unitPrice = '100000';
        if (!type.isVehicle) line.quantity = '3';
      });
      expect(controller.singlePaid, type.isVehicle ? 100000 : 300000);
      expect(controller.singleRemaining, 0);
      controller.setPaidAmount('20000');
      controller.updateLine(
        controller.lines.single,
        (line) => line.unitPrice = '200000',
      );
      expect(controller.singlePaid, 20000);
      expect(controller.singleRemaining, controller.total - 20000);
    }
  });
  test(
    'Single receipt keeps carrier and payment, rejects overpayment, inherits existing lots',
    () {
      final controller = GoodsReceiptController(ReceiptProductType.part);
      addTearDown(controller.dispose);
      controller.updateLine(controller.lines.single, (l) {
        l.name = 'Nhớt';
        l.quantity = '3';
        l.unitPrice = '100000';
      });
      controller.setPaidAmount('100000');
      controller.changeCarrier('Người giao thử');
      expect(controller.validate(), contains('Vui lòng chọn vận chuyển'));
      controller.selectCarrier('carrier-test', 'Người giao thử');
      var receipt = controller.preview();
      expect(receipt.carrierId, 'carrier-test');
      expect(receipt.carrier, 'Người giao thử');
      expect(receipt.paidAmount, 100000);
      expect(receipt.remainingAmount, 200000);
      controller.updateLine(
        controller.lines.single,
        (l) => l.unitPrice = '50000',
      );
      expect(controller.singleRemaining, 50000);
      expect(receipt.remainingAmount, 200000);
      controller.setPaidAmount('150001');
      expect(controller.validate(), contains('vượt tổng tiền'));
      controller.setPaidAmount('-1');
      expect(controller.validate(), contains('không âm'));
      controller.setPaidAmount('150000');
      expect(controller.preview().remainingAmount, 0);
      controller.changeCarrier('');
      controller.setPaidAmount('0');
      receipt = controller.preview();
      expect(receipt.carrierId, isNull);
      expect(receipt.remainingAmount, 150000);
      final existing = GoodsReceiptController(
        ReceiptProductType.part,
        targetBatchId: 42,
      );
      addTearDown(existing.dispose);
      existing.updateLine(existing.lines.single, (l) {
        l.name = 'Nhớt';
        l.unitPrice = '100000';
      });
      existing.setPaidAmount('999999');
      existing.changeCarrier('Không ghi đè vận chuyển lô');
      expect(existing.preview().paidAmount, 0);
      expect(existing.preview().carrierId, isNull);
    },
  );

  test('Single and batch retain independent rows and exact totals', () {
    final controller = GoodsReceiptController(ReceiptProductType.part);
    addTearDown(controller.dispose);
    controller.updateLine(controller.lines.single, (line) {
      line.name = 'Nhớt';
      line.quantity = '3';
      line.unitPrice = '125000';
    });
    expect(controller.total, 375000);
    final snapshot = controller.preview();
    controller.setMode(ReceiptMode.batch);
    prepareBatch(controller, quantity: '6', total: '200000');
    controller.updateLine(controller.lines.single, (line) {
      line.name = 'Bugi';
      line.quantity = '2';
      line.unitPrice = '50000';
    });
    controller.addLine();
    controller.updateLine(controller.lines.last, (line) {
      line.name = 'Lọc gió';
      line.quantity = '4';
      line.unitPrice = '25000';
    });
    expect(controller.preview().total, 200000);
    expect(controller.totalQuantity, 6);
    controller.removeLine(controller.lines.last);
    expect(controller.total, 100000);
    controller.removeLine(controller.lines.single);
    expect(controller.lines.length, 1);
    controller.setMode(ReceiptMode.single);
    expect(controller.lines.single.name, 'Nhớt');
    expect(controller.total, 375000);
    controller.updateLine(
      controller.lines.single,
      (line) => line.unitPrice = '100000',
    );
    expect(snapshot.total, 375000);
  });

  test(
    'Each vehicle has quantity one and duplicate identifiers are rejected',
    () {
      final controller = GoodsReceiptController(ReceiptProductType.newVehicle);
      addTearDown(controller.dispose);
      controller.setMode(ReceiptMode.batch);
      prepareBatch(controller, quantity: '2', total: '50000000');
      controller.updateLine(controller.lines.single, (line) {
        line.name = 'Xe A';
        line.unitPrice = '20000000';
        line.quantity = '20';
        line.frameNumber = 'abc';
      });
      controller.addLine();
      controller.updateLine(controller.lines.last, (line) {
        line.name = 'Xe B';
        line.unitPrice = '30000000';
        line.frameNumber = ' ABC ';
      });
      expect(controller.totalQuantity, 2);
      expect(controller.total, 50000000);
      expect(controller.validate(), contains('Số khung bị trùng'));
      expect(() => controller.preview(), throwsStateError);
      controller.updateLine(
        controller.lines.last,
        (line) => line.frameNumber = 'XYZ',
      );
      expect(controller.validate(), isNull);
      expect(
        controller.preview().lines.every((line) => line.quantity == 1),
        isTrue,
      );
    },
  );

  test(
    'Batch header must be confirmed; payment balance and source fields are retained',
    () {
      final controller = GoodsReceiptController(ReceiptProductType.newVehicle);
      addTearDown(controller.dispose);
      controller.setMode(ReceiptMode.batch);
      expect(controller.showProductForm, isFalse);
      expect(controller.confirmBatch(), isNotNull);
      controller.addLine();
      expect(controller.lines.length, 1);
      expect(() => controller.preview(), throwsStateError);
      controller.updateBatch((batch) {
        batch.quantity = '2';
        batch.totalAmount = '40000000';
        batch.paidAmount = '10000000';
        batch.deliveredBy = 'Người giao thử';
        batch.origin = 'Nơi nhập thử';
        batch.partnerId = 'partner-test';
        batch.carrierId = 'carrier-test';
      });
      expect(controller.batchRemaining, 30000000);
      expect(controller.confirmBatch(), isNull);
      expect(controller.showProductForm, isTrue);
      controller.updateLine(controller.lines.single, (line) {
        line.name = 'Xe A';
        line.unitPrice = '20000000';
      });
      final fields = controller.preview().batchInfo!.toDatabaseFields();
      expect(fields.keys.toSet(), {
        'SoLuong',
        'SoTien',
        'NguoiCho',
        'NoiNhap',
        'NgayNhap',
        'SoTienDaTra',
        'SoTienConNo',
        'IdDoiTac',
        'IdVanChuyen',
      });
      expect(fields['SoTienConNo'], 30000000);
      controller.editBatch();
      expect(controller.showProductForm, isFalse);
      expect(controller.lines.single.name, 'Xe A');
      controller.updateBatch((batch) => batch.paidAmount = '50000000');
      expect(controller.confirmBatch(), contains('không được lớn hơn'));
      expect(controller.showProductForm, isFalse);
      controller.updateBatch((batch) => batch.paidAmount = '10000000');
      expect(controller.confirmBatch(), isNull);
      expect(controller.lines.single.name, 'Xe A');
    },
  );

  test('Missing name, price and zero part quantities cannot be previewed', () {
    final controller = GoodsReceiptController(ReceiptProductType.part);
    addTearDown(controller.dispose);
    expect(controller.validate(), isNotNull);
    controller.updateLine(
      controller.lines.single,
      (line) => line.name = 'Nhớt',
    );
    expect(controller.validate(), isNotNull);
    controller.updateLine(controller.lines.single, (line) {
      line.unitPrice = '50000';
      line.quantity = '0';
    });
    expect(controller.validate(), contains('Số lượng'));
  });
  test(
    'New vehicle lot fields map to Xe and XeMoi without inventing IDs or status codes',
    () async {
      final repository = FakeDirectoryRepository();
      final controller = GoodsReceiptController(
        ReceiptProductType.newVehicle,
        targetBatchId: 42,
        directoryRepository: repository,
      );
      addTearDown(controller.dispose);
      await controller.loadBrands();
      final draft = controller.lines.single;
      controller.selectBrand(draft, 1);
      controller.updateLine(draft, (line) {
        line.name = 'Wave';
        line.unitPrice = '20000000';
        line.salePrice = '25000000';
        line.registrationFee = '420000';
        line.frameNumber = 'KHUNG-7';
        line.engineNumber = 'MAY-7';
      });
      final receipt = controller.preview();
      expect(receipt.batchId, 42);
      expect(receipt.total, 20000000);
      final line = receipt.lines.single;
      final vehicle = line.toVehicleFields(
        ReceiptProductType.newVehicle,
        vehicleId: 7,
        productId: 10,
      );
      expect(vehicle['IdHangXe'], 1);
      expect(vehicle['GiaBan'], 25000000);
      expect(vehicle['TinhTrang'], isTrue);
      final extension = line.toVehicleDetailFields(
        ReceiptProductType.newVehicle,
        vehicleId: 7,
        batchId: receipt.batchId,
      );
      expect(extension['IdNhapHang'], 42);
      expect(extension['TienDangKy'], 420000);
      expect(extension['SoKhung'], 'KHUNG-7');
      expect(extension['SoMay'], 'MAY-7');
      expect(extension['TrangThai'], isNull);
      controller.updateLine(draft, (line) => line.registrationFee = '0');
      expect(receipt.lines.single.registrationFee, 420000);
      controller.updateLine(draft, (line) => line.salePrice = '-1');
      expect(controller.validate(), contains('Giá bán'));
    },
  );
  test(
    'Used vehicle notes and part catalog/unit/stock fields follow their own collections',
    () {
      final used = GoodsReceiptController(ReceiptProductType.usedVehicle);
      addTearDown(used.dispose);
      used.updateLine(used.lines.single, (line) {
        line.name = 'Xe cũ';
        line.unitPrice = '1000000';
        line.salePrice = '1500000';
        line.plate = '21A-001';
        line.vehicleNotes = 'Xe đã qua sử dụng';
      });
      final details = used.preview().lines.single.toVehicleDetailFields(
        ReceiptProductType.usedVehicle,
        vehicleId: 8,
      );
      expect(details, {
        'IdXe': 8,
        'BienSo': '21A-001',
        'MauSon': '',
        'GhiChu': 'Xe đã qua sử dụng',
      });
      final parts = GoodsReceiptController(ReceiptProductType.part);
      addTearDown(parts.dispose);
      parts.updateLine(parts.lines.single, (line) {
        line.name = 'Bugi';
        line.unitPrice = '20000';
        line.salePrice = '30000';
        line.productCode = 'PT-BUGI';
        line.unit = 'hộp';
        line.quantity = '3';
      });
      final line = parts.preview().lines.single;
      final catalog = line.toCatalogFields(
        ReceiptProductType.part,
        productId: 15,
        generatedCode: 'PT-15',
      );
      expect(catalog['MaSanPham'], 'PT-BUGI');
      expect(catalog['DonViTinh'], 'hộp');
      expect(catalog['GiaBanThamKhao'], 30000);
      expect(line.toPartStockFields(productId: 15), {
        'IdSanPham': 15,
        'SoLuongTon': 3,
        'GiaVonThamKhao': 20000,
      });
      parts.updateLine(parts.lines.single, (line) => line.unit = '');
      expect(parts.validate(), contains('đơn vị tính'));
    },
  );
  test(
    'Optional source fields stay null and a failed brand lookup can retry',
    () async {
      final repository = FakeDirectoryRepository()..failBrands = true;
      final controller = GoodsReceiptController(
        ReceiptProductType.newVehicle,
        directoryRepository: repository,
      );
      addTearDown(controller.dispose);
      await controller.loadBrands();
      expect(controller.brandsError, isNotNull);
      repository.failBrands = false;
      await controller.loadBrands();
      expect(controller.brandsError, isNull);
      expect(controller.brands.length, 2);
      controller.updateLine(controller.lines.single, (line) {
        line.name = 'Xe';
        line.unitPrice = '0';
      });
      final line = controller.preview().lines.single;
      expect(line.brandId, isNull);
      expect(line.salePrice, isNull);
      expect(line.registrationFee, isNull);
    },
  );
}
