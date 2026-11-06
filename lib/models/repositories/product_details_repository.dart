import '../maintenance/record_maintenance.dart';
import '../products/product_details.dart';

abstract class ProductDetailsRepository {
  RecordMaintenance? get maintenance => null;
  Future<ProductDetails> load(ProductReference product);
  Future<void> update(ProductReference product, ProductEditDraft draft);
  Future<void> delete(ProductReference product);
  Future<void> archive(ProductReference product) => delete(product);
  Future<void> addCost(
    ProductReference product, {
    required DateTime date,
    required int amount,
    required String notes,
    required String requestId,
  });
  Future<void> close();
}
