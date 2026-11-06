import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/cart_controller.dart';

void main() {
  test(
    'Vehicle is unique; parts cannot exceed stock; removal releases item',
    () {
      final cart = CartController();
      final vehicle = {'IdXe': 1, 'TenXe': 'Xe mới', 'SoLuongTon': 1};
      expect(cart.add(vehicle, vehicle: true), isTrue);
      expect(cart.add(vehicle, vehicle: true), isFalse);
      expect(cart.add({'IdXe': 2, 'SoLuongTon': 0}, vehicle: true), isFalse);
      expect(cart.add({'IdSanPham': 2}, vehicle: false), isFalse);
      final part = {'IdSanPham': 1, 'SoLuongTon': 2};
      expect(cart.add(part, vehicle: false), isTrue);
      expect(cart.add(part, vehicle: false), isTrue);
      expect(cart.add(part, vehicle: false), isFalse);
      expect(cart.count, 3);
      cart.remove(cart.items.first);
      expect(cart.count, 2);
      expect(cart.add(vehicle, vehicle: true), isTrue);
    },
  );
}
