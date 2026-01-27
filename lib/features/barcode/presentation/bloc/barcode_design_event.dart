import '../../../../core/bloc/realtime_bloc.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../../core/database/app_database.dart' hide Product;
import '../../domain/models/barcode_design_state.dart';

abstract class BarcodeDesignEvent extends RealtimeEvent {
  const BarcodeDesignEvent();
}

/// Load initial data (templates, default settings)
class LoadBarcodeDesignData extends BarcodeDesignEvent {
  final List<Product>? initialProducts;
  final Map<int, String>? variantInfoByProductId;

  const LoadBarcodeDesignData({
    this.initialProducts,
    this.variantInfoByProductId,
  });
}

/// Add products to selection
class AddProductsToSelection extends BarcodeDesignEvent {
  final List<Product> products;

  const AddProductsToSelection(this.products);
}

/// Remove product from selection
class RemoveProductFromSelection extends BarcodeDesignEvent {
  final int productId;

  const RemoveProductFromSelection(this.productId);
}

/// Clear all selected products
class ClearProductSelection extends BarcodeDesignEvent {
  const ClearProductSelection();
}

/// Select a template
class SelectTemplate extends BarcodeDesignEvent {
  final BarcodeTemplate template;

  const SelectTemplate(this.template);
}

/// Update design settings
class UpdateDesignSettings extends BarcodeDesignEvent {
  final BarcodeDesignSettings settings;

  const UpdateDesignSettings(this.settings);
}

/// Update label dimensions
class UpdateLabelDimensions extends BarcodeDesignEvent {
  final double? widthMm;
  final double? heightMm;

  const UpdateLabelDimensions({this.widthMm, this.heightMm});
}

/// Toggle include name
class ToggleIncludeName extends BarcodeDesignEvent {
  final bool value;
  const ToggleIncludeName(this.value);
}

/// Toggle include price
class ToggleIncludePrice extends BarcodeDesignEvent {
  final bool value;
  const ToggleIncludePrice(this.value);
}

/// Toggle include SKU
class ToggleIncludeSku extends BarcodeDesignEvent {
  final bool value;
  const ToggleIncludeSku(this.value);
}

/// Toggle include company name
class ToggleIncludeCompanyName extends BarcodeDesignEvent {
  final bool value;
  const ToggleIncludeCompanyName(this.value);
}

/// Toggle include company contact (address + phone)
class ToggleIncludeCompanyContact extends BarcodeDesignEvent {
  final bool value;
  const ToggleIncludeCompanyContact(this.value);
}

/// Toggle include variant info
class ToggleIncludeVariantInfo extends BarcodeDesignEvent {
  final bool value;
  const ToggleIncludeVariantInfo(this.value);
}

/// Update barcode type
class UpdateBarcodeType extends BarcodeDesignEvent {
  final String barcodeType;

  const UpdateBarcodeType(this.barcodeType);
}

/// Update copies count
class UpdateCopies extends BarcodeDesignEvent {
  final int copies;

  const UpdateCopies(this.copies);
}

/// Update print type
class UpdatePrintType extends BarcodeDesignEvent {
  final String printType;

  const UpdatePrintType(this.printType);
}

/// Print labels for selected products
class PrintLabels extends BarcodeDesignEvent {
  final String? printerName;

  const PrintLabels({this.printerName});
}

/// Share labels as PDF
class ShareLabels extends BarcodeDesignEvent {
  const ShareLabels();
}

/// Save current settings as a new template
class SaveAsTemplate extends BarcodeDesignEvent {
  final String name;
  final String? description;

  const SaveAsTemplate({required this.name, this.description});
}

/// Acknowledge print result (reset status)
class AcknowledgePrintResult extends BarcodeDesignEvent {
  const AcknowledgePrintResult();
}
