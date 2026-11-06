import 'package:flutter/foundation.dart';
import '../models/services/service_models.dart';

class CartItem {
  CartItem(this.product, this.vehicle) {
    final price = service
        ? product['GiaTien']
        : vehicle
        ? null
        : product['GiaBanThamKhao'];
    priceText = price is num && price >= 0 && price == price.roundToDouble()
        ? price.toInt().toString()
        : '';
  }
  final Map<String, dynamic> product;
  final bool vehicle;
  int quantity = 1;
  String priceText = '';
  bool get service => product['LoaiSanPham'] == 'dich_vu';
  int? get unitPrice => RegExp(r'^\d+$').hasMatch(priceText.trim())
      ? int.tryParse(priceText.trim())
      : null;
  int? get total => unitPrice == null ? null : unitPrice! * quantity;
  String get key =>
      '${service
          ? 'dv'
          : vehicle
          ? 'xe'
          : 'pt'}-${product[service
          ? '_id'
          : vehicle
          ? 'IdXe'
          : 'IdSanPham']}';
  String get name =>
      '${product[service
              ? 'TenDichVu'
              : vehicle
              ? 'TenXe'
              : 'TenSanPham'] ?? ''}';
}

/// Shared order draft; stock changes only after a future checkout.
class CartController extends ChangeNotifier {
  static final shared = CartController();
  final List<CartItem> _items = [];
  bool _locked = false;
  bool get locked => _locked;
  void setLocked(bool value) {
    _locked = value;
    notifyListeners();
  }

  List<CartItem> get items => List.unmodifiable(_items);
  int get count => _items.fold(0, (n, item) => n + item.quantity);
  bool add(Map<String, dynamic> product, {required bool vehicle}) {
    if (_locked) return false;
    final service = product['LoaiSanPham'] == 'dich_vu';
    final stock = product['SoLuongTon'];
    if (!service && (stock is! num || stock < 1)) return false;
    final candidate = CartItem(Map.of(product), vehicle);
    final matches = _items.where((item) => item.key == candidate.key);
    if (matches.isEmpty) {
      _items.add(candidate);
    } else {
      final item = matches.first;
      if (vehicle || (!service && item.quantity + 1 > stock)) return false;
      item.quantity++;
    }
    notifyListeners();
    return true;
  }

  bool addService(ServiceItem service) => add({
    '_id': service.id,
    'LoaiSanPham': 'dich_vu',
    'TenDichVu': service.name,
    'MoTa': service.description,
    'GiaTien': service.price,
  }, vehicle: false);
  void setPrice(CartItem item, String text) {
    if (_locked || !_items.contains(item)) return;
    item.priceText = text;
    notifyListeners();
  }

  bool setQuantity(CartItem item, int quantity) {
    if (_locked ||
        !_items.contains(item) ||
        quantity < 1 ||
        (item.vehicle && quantity != 1)) {
      return false;
    }
    if (!item.service) {
      final stock = item.product['SoLuongTon'];
      if (stock is! num || quantity > stock) return false;
    }
    item.quantity = quantity;
    notifyListeners();
    return true;
  }

  void remove(CartItem item) {
    if (_locked) return;
    _items.remove(item);
    notifyListeners();
  }

  void clear() {
    if (_locked) return;
    _items.clear();
    notifyListeners();
  }
}
