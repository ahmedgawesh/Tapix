 import 'package:flutter/foundation.dart';
 
 @immutable
 class InvoicePrintData {
   final List<InvoiceLinePrintData> lines;
   final String invoiceType;
   final int invoiceId;
   final String invoiceNumber;
   final DateTime invoiceDate;
 
   const InvoicePrintData({
     required this.lines,
     required this.invoiceType,
     required this.invoiceId,
     required this.invoiceNumber,
     required this.invoiceDate,
   });
 }
 
 @immutable
 class InvoiceLinePrintData {
   final int variantId;
   final int quantity;
   final String productName;
   final String? colorName;
   final String? sizeName;
   final String barcode;
   final String sku;
   final int unitPriceCents;
   final bool isActive;
 
   const InvoiceLinePrintData({
     required this.variantId,
     required this.quantity,
     required this.productName,
     this.colorName,
     this.sizeName,
     required this.barcode,
     required this.sku,
     required this.unitPriceCents,
     required this.isActive,
   });
 }
 
 class InvoiceNotFoundException implements Exception {
   final int invoiceId;
   final String invoiceType;
 
   InvoiceNotFoundException(this.invoiceId, this.invoiceType);
 
   @override
   String toString() => 'InvoiceNotFoundException($invoiceType#$invoiceId)';
 }
 
 class InvoiceNotPostedException implements Exception {
   final int invoiceId;
   final String invoiceType;
 
   InvoiceNotPostedException(this.invoiceId, this.invoiceType);
 
   @override
   String toString() => 'InvoiceNotPostedException($invoiceType#$invoiceId)';
 }
