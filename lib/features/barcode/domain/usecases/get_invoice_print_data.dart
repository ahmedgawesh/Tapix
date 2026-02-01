 import '../../data/models/invoice_print_data.dart';
 import '../../data/repositories/barcode_repository.dart';
 
 class GetInvoicePrintData {
   final BarcodeRepository _repository;
 
   GetInvoicePrintData(this._repository);
 
   Future<InvoicePrintData> forPurchase(int purchaseId) {
     return _repository.getPurchasePrintData(purchaseId);
   }
 
   Future<InvoicePrintData> forSale(int saleId) {
     return _repository.getSalePrintData(saleId);
   }
 }
