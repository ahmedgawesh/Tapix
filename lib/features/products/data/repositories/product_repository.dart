import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/product_dao.dart';

class ProductRepository {
  final ProductDao _productDao;

  ProductRepository(this._productDao);

  Stream<List<Product>> watchAllProducts() => _productDao.watchAllProducts();

  Stream<Product?> watchProduct(int id) => _productDao.watchProduct(id);

  Future<List<Product>> searchProducts(String query) => _productDao.searchProducts(query);

  Future<Product?> findBySku(String sku) => _productDao.findBySku(sku);

  Future<Product?> findByBarcode(String barcode) => _productDao.findByBarcode(barcode);

  Future<List<Product>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
  }) => _productDao.filterProducts(
        categoryId: categoryId,
        stockStatus: stockStatus,
        limit: limit,
        offset: offset,
      );

  Stream<List<Product>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
  }) => _productDao.watchFilteredProducts(
        categoryId: categoryId,
        stockStatus: stockStatus,
      );

  Future<int> createProduct({
    required String sku,
    required String name,
    String? description,
    int? categoryId,
    required Decimal costCents,
    required Decimal priceCents,
    required int currencyId,
    bool trackInventory = true,
    int stockQuantity = 0,
    int? reorderLevel,
    bool hasVariants = false,
  }) {
    return _productDao.createProduct(
      ProductsCompanion.insert(
        sku: sku,
        name: name,
        description: Value(description),
        categoryId: Value(categoryId),
        costCents: costCents,
        priceCents: priceCents,
        currencyId: currencyId,
        trackInventory: Value(trackInventory),
        stockQuantity: Value(stockQuantity),
        reorderLevel: Value(reorderLevel),
        hasVariants: Value(hasVariants),
      ),
    );
  }

  Future<bool> updateProduct(Product product) => _productDao.updateProduct(product);

  Future<int> deleteProduct(int id) => _productDao.deleteProduct(id);

  Stream<List<ProductVariant>> watchProductVariants(int productId) =>
      _productDao.watchProductVariants(productId);

  Stream<List<ProductCategory>> watchCategories() => _productDao.watchCategories();
}
