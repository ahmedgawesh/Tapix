import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/business/warehouse_read_scope.dart';
import '../../../settings/domain/entities/company_profile.dart';

/// Carries a fixed, authorized warehouse through a report route and exports.
class WarehouseReportContext extends InheritedWidget {
  const WarehouseReportContext({
    super.key,
    required this.scope,
    required this.name,
    required this.code,
    required super.child,
  });
  final WarehouseReadScope scope;
  final String name, code;
  static WarehouseReportContext? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WarehouseReportContext>();
  String get label => '${'warehouse_setup.warehouse'.tr()}: $name · $code';
  CompanyProfile decorateCompany(CompanyProfile profile) =>
      profile.copyWith(name: '${profile.name}\n$label');
  @override
  bool updateShouldNotify(WarehouseReportContext oldWidget) =>
      scope != oldWidget.scope ||
      name != oldWidget.name ||
      code != oldWidget.code;
}
