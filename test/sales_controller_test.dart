import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/cart_controller.dart';
import 'package:xemay_app/controllers/sales_controller.dart';
import 'package:xemay_app/models/services/service_models.dart';
import 'package:xemay_app/models/sales/sale_models.dart';
import 'support/fake_customer_repository.dart';
import 'support/fake_sales_repository.dart';

void main() {
  test(
    'Manual vehicle price, stock limits, service quantities and payment balance',
    () {
      final cart = CartController();
      final sale = SalesController(cart, FakeCustomerRepository());
      cart.add({
        'IdXe': 7,
        'TenXe': 'Xe',
        'GiaBan': 999999,
        'SoLuongTon': 1,
      }, vehicle: true);
      expect(sale.subtotal, isNull);
      expect(sale.validationError, contains('giá bán'));
      final vehicle = cart.items.first;
      cart.setPrice(vehicle, '1000000');
      expect(cart.setQuantity(vehicle, 2), isFalse);
      cart.addService(
        const ServiceItem(
          id: 'service-1',
          name: 'Thay dầu',
          description: '',
          price: 150000,
        ),
      );
      final service = cart.items.last;
      expect(cart.setQuantity(service, 2), isTrue);
      expect(sale.subtotal, 1300000);
      sale.setDiscount('100000');
      sale.setPaid('500000');
      expect(sale.total, 1200000);
      expect(sale.due, 700000);
      expect(sale.change, 0);
      sale.setPaid('1500000');
      expect(sale.change, 300000);
      expect(sale.due, 0);
      sale.setPaid('${sale.total}');
      expect(sale.paid, 1200000);
      expect(sale.change, 0);
      sale.setDiscount('9999999');
      expect(sale.discountError, isNotNull);
      expect(sale.total, isNull);
      sale.clear();
      expect(cart.items, isEmpty);
      expect(sale.customerQuery, isEmpty);
      sale.dispose();
    },
  );
  test('Unselected typed customer and invalid payment cannot be previewed', () {
    final cart = CartController()
      ..addService(
        const ServiceItem(id: 's', name: 'Dịch vụ', description: '', price: 0),
      );
    final sale = SalesController(cart, FakeCustomerRepository());
    sale.customerTextChanged('Tên chưa chọn');
    expect(sale.validationError, contains('Chọn khách hàng'));
    sale.clearCustomer();
    expect(sale.validationError, isNull);
    sale.setPaid('-10');
    expect(sale.paidError, isNotNull);
    expect(sale.due, isNull);
    sale.dispose();
  });
  test(
    'Unknown save outcome keeps immutable request and stock locked until same-key retry succeeds',
    () async {
      final cart = CartController()
        ..addService(
          const ServiceItem(
            id: 's',
            name: 'Dịch vụ',
            description: '',
            price: 50000,
          ),
        );
      final repo = FakeSalesRepository()
        ..fail = true
        ..uncertain = true;
      final sale = SalesController(
        cart,
        FakeCustomerRepository(),
        salesRepository: repo,
      );
      sale.setPaid('50000');
      expect(await sale.save(), isNull);
      expect(sale.awaitingConfirmation, isTrue);
      expect(cart.locked, isTrue);
      expect(
        cart.addService(
          const ServiceItem(
            id: 'other',
            name: 'Khác',
            description: '',
            price: 1,
          ),
        ),
        isFalse,
      );
      cart.setPrice(cart.items.single, '1');
      expect(cart.items.single.unitPrice, 50000);
      repo.fail = false;
      final result = await sale.save();
      expect(result!.invoiceId, 501);
      expect(repo.requestIds.first, repo.requestIds.last);
      expect(cart.items, isEmpty);
      expect(sale.lastSavedId, 501);
      expect(cart.locked, isFalse);
      sale.dispose();
    },
  );
  test(
    'Rejected sale preserves draft and allows corrections; unidentified debt cannot save',
    () async {
      final cart = CartController()
        ..addService(
          const ServiceItem(
            id: 's',
            name: 'Dịch vụ',
            description: '',
            price: 50000,
          ),
        );
      final repo = FakeSalesRepository()..fail = true;
      final sale = SalesController(
        cart,
        FakeCustomerRepository(),
        salesRepository: repo,
      );
      expect(await sale.save(), isNull);
      expect(repo.calls, 0);
      sale.setPaid('50000');
      expect(await sale.save(), isNull);
      expect(cart.locked, isFalse);
      expect(cart.items.length, 1);
      repo.fail = false;
      expect(await sale.save(), isNotNull);
      expect(repo.requestIds.first, isNot(repo.requestIds.last));
      sale.dispose();
    },
  );
  test(
    'Credit order requires dates, snapshots them, and omits them when paid in full',
    () {
      final cart = CartController()
        ..addService(
          const ServiceItem(
            id: 's',
            name: 'Dịch vụ',
            description: '',
            price: 50000,
          ),
        );
      final sale = SalesController(cart, FakeCustomerRepository());
      sale.setDate(DateTime(2026, 11, 4));
      sale.selectCustomer({'IdKH': 1, 'TenKhachHang': 'Khách'});
      sale.setPaid('10000');
      expect(sale.hasDebt, isTrue);
      expect(sale.validationError, contains('ngày hẹn'));
      sale.setPaymentDueDate(DateTime(2026, 11, 30));
      expect(sale.validationError, contains('ngày tính lãi'));
      sale.setInterestDate(DateTime(2026, 11, 5));
      expect(sale.validationError, isNull);
      expect(sale.snapshot().error, isNull);
      expect(sale.snapshot().toMap()['NgayHen'], '2026-11-30');
      expect(sale.snapshot().toMap()['NgayTinhLai'], '2026-11-05');
      sale.setInterestDate(DateTime(2026, 11, 3));
      expect(sale.validationError, contains('trước ngày bán'));
      sale.setPaid('50000');
      expect(sale.hasDebt, isFalse);
      expect(sale.validationError, isNull);
      expect(sale.snapshot().toMap()['NgayHen'], isNull);
      expect(sale.snapshot().toMap()['NgayTinhLai'], isNull);
      sale.clear();
      expect(sale.paymentDueDate, isNull);
      expect(sale.interestDate, isNull);
      sale.dispose();
    },
  );
  test(
    'Legacy write journal keeps its original payload without invented credit dates',
    () {
      final original = <String, dynamic>{
        'IdKH': 1,
        'NgayBan': '2026-11-04',
        'GhiChu': '',
        'GiamGia': 0,
        'SoTienKhachDua': 10000,
        'ChiTiet': [
          {
            'LoaiSanPham': 'dich_vu',
            'TenSanPham': 'Dịch vụ',
            'IdSanPham': null,
            'IdXe': null,
            'IdDichVu': 's',
            'SoLuong': 1,
            'DonGia': 50000,
          },
        ],
      };
      final restored = SaleDraft.fromMap(original);
      expect(restored.debtDatesVersion, 0);
      expect(restored.toMap(), original);
      expect(restored.storedDueDate, isNull);
    },
  );
}
