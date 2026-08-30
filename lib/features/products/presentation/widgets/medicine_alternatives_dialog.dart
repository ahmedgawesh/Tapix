import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/daos/pharmacy_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/services/pharmacy/medicine_normalization_service.dart';

class MedicineAlternativesDialog extends StatelessWidget {
  const MedicineAlternativesDialog._({
    required this.productId,
    required this.allowSelection,
    required this.outOfStock,
  });

  final int productId;
  final bool allowSelection;
  final bool outOfStock;

  static Future<int?> show(
    BuildContext context, {
    required int productId,
    bool allowSelection = false,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => MedicineAlternativesDialog._(
        productId: productId,
        allowSelection: allowSelection,
        outOfStock: false,
      ),
    );
  }

  static Future<int?> showOutOfStock(
    BuildContext context, {
    required int productId,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => MedicineAlternativesDialog._(
        productId: productId,
        allowSelection: true,
        outOfStock: true,
      ),
    );
  }

  Future<
    ({
      MedicineProfileDetails? source,
      List<MedicineProfileDetails> alternatives,
    })
  >
  _load() async {
    final dao = sl<PharmacyDao>();
    final source = await dao.getMedicineProfile(productId);
    final alternatives = source == null
        ? const <MedicineProfileDetails>[]
        : await dao.findExactAlternatives(productId);
    return (source: source, alternatives: alternatives);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        outOfStock ? LucideIcons.alertTriangle : LucideIcons.pill,
        color: outOfStock ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text(
        outOfStock
            ? 'sales.out_of_stock_warning'.tr()
            : 'pharmacy.alternatives.title'.tr(),
      ),
      content: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height * 0.65,
        child:
            FutureBuilder<
              ({
                MedicineProfileDetails? source,
                List<MedicineProfileDetails> alternatives,
              })
            >(
              future: _load(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('common.error'.tr()));
                }
                final source = snapshot.data?.source;
                if (source == null) {
                  return Center(
                    child: Text('pharmacy.alternatives.not_medicine'.tr()),
                  );
                }
                final alternatives = snapshot.data!.alternatives
                    .where(
                      (alternative) =>
                          !outOfStock || alternative.product.stockQuantity > 0,
                    )
                    .toList(growable: false);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FormulaHeader(details: source),
                    const Divider(height: 24),
                    if (alternatives.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text('pharmacy.alternatives.none'.tr()),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: alternatives.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final alternative = alternatives[index];
                            return ListTile(
                              leading: const CircleAvatar(
                                child: Icon(LucideIcons.pill),
                              ),
                              title: Text(alternative.product.name),
                              subtitle: Text(
                                '${_formula(context, alternative)}\n'
                                '${'pharmacy.alternatives.available'.tr()}: '
                                '${localizedQuantity(alternative.product.stockQuantity, alternative.product.measurementType)}',
                              ),
                              isThreeLine: true,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    sl<CurrencyService>().format(
                                      alternative.product.priceCents
                                          .toBigInt()
                                          .toInt(),
                                    ),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (allowSelection)
                                    Text(
                                      'pharmacy.alternatives.select'.tr(),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                ],
                              ),
                              onTap: allowSelection
                                  ? () => Navigator.pop(
                                      context,
                                      alternative.product.id,
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.close'.tr()),
        ),
      ],
    );
  }
}

class RemoteMedicineAlternativesDialog extends StatelessWidget {
  const RemoteMedicineAlternativesDialog._({
    required this.source,
    required this.outOfStock,
  });

  final LanCatalogProduct source;
  final bool outOfStock;

  static Future<LanCatalogProduct?> show(
    BuildContext context, {
    required LanCatalogProduct source,
  }) {
    return showDialog<LanCatalogProduct>(
      context: context,
      builder: (_) =>
          RemoteMedicineAlternativesDialog._(source: source, outOfStock: false),
    );
  }

  static Future<LanCatalogProduct?> showOutOfStock(
    BuildContext context, {
    required LanCatalogProduct source,
  }) {
    return showDialog<LanCatalogProduct>(
      context: context,
      builder: (_) =>
          RemoteMedicineAlternativesDialog._(source: source, outOfStock: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        outOfStock ? LucideIcons.alertTriangle : LucideIcons.pill,
        color: outOfStock ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text(
        outOfStock
            ? 'sales.out_of_stock_warning'.tr()
            : 'pharmacy.alternatives.title'.tr(),
      ),
      content: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: FutureBuilder<LanMedicineAlternativesResult>(
          future: sl<LanNetworkService>().fetchRemoteMedicineAlternatives(
            source.id,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('common.error'.tr()));
            }
            final medicine = source.medicine;
            if (medicine == null) {
              return Center(
                child: Text('pharmacy.alternatives.not_medicine'.tr()),
              );
            }
            final alternatives =
                (snapshot.data?.alternatives ?? const <LanCatalogProduct>[])
                    .where(
                      (alternative) =>
                          !outOfStock || alternative.stockQuantity > 0,
                    )
                    .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  source.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${'pharmacy.alternatives.formula'.tr()}: '
                  '${_remoteFormula(context, medicine)}',
                ),
                const Divider(height: 24),
                if (alternatives.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text('pharmacy.alternatives.none'.tr()),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: alternatives.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final alternative = alternatives[index];
                        final alternativeMedicine = alternative.medicine;
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(LucideIcons.pill),
                          ),
                          title: Text(alternative.name),
                          subtitle: Text(
                            '${alternativeMedicine == null ? '' : _remoteFormula(context, alternativeMedicine)}\n'
                            '${'pharmacy.alternatives.available'.tr()}: '
                            '${localizedQuantity(alternative.stockQuantity, alternative.measurementType)}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                sl<CurrencyService>().format(
                                  alternative.priceCents,
                                ),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'pharmacy.alternatives.select'.tr(),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                          onTap: () => Navigator.pop(context, alternative),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.close'.tr()),
        ),
      ],
    );
  }
}

class _FormulaHeader extends StatelessWidget {
  const _FormulaHeader({required this.details});

  final MedicineProfileDetails details;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          details.product.name,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '${'pharmacy.alternatives.formula'.tr()}: ${_formula(context, details)}',
        ),
        const SizedBox(height: 4),
        Text(
          '${'pharmacy.form.dosage_form'.tr()}: '
          '${'pharmacy.forms.${details.profile.dosageForm}'.tr()} • '
          '${'pharmacy.form.route'.tr()}: '
          '${'pharmacy.routes.${details.profile.administrationRoute}'.tr()}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

String _formula(BuildContext context, MedicineProfileDetails details) {
  const normalization = MedicineNormalizationService();
  return details.ingredients
      .map((row) {
        final localized = context.locale.languageCode == 'ar'
            ? row.ingredient.nameAr
            : context.locale.languageCode == 'fr'
            ? row.ingredient.nameFr
            : null;
        final name = localized?.trim().isNotEmpty == true
            ? localized!
            : row.ingredient.canonicalName;
        final strength = row.strength;
        final value = normalization.editableValue(
          strength.normalizedStrengthValueMicros,
        );
        final basis = strength.normalizedBasisValueMicros == null
            ? ''
            : ' / ${normalization.editableValue(strength.normalizedBasisValueMicros!)} ${strength.normalizedBasisUnit}';
        return '$name $value ${strength.normalizedStrengthUnit}$basis';
      })
      .join(' + ');
}

String _remoteFormula(BuildContext context, LanMedicineProfile medicine) {
  const normalization = MedicineNormalizationService();
  return medicine.ingredients
      .map((row) {
        final localized = context.locale.languageCode == 'ar'
            ? row.nameAr
            : context.locale.languageCode == 'fr'
            ? row.nameFr
            : null;
        final name = localized?.trim().isNotEmpty == true
            ? localized!
            : row.canonicalName;
        final value = normalization.editableValue(row.strengthValueMicros);
        final basis = row.basisValueMicros == null
            ? ''
            : ' / ${normalization.editableValue(row.basisValueMicros!)} ${row.basisUnit}';
        return '$name $value ${row.strengthUnit}$basis';
      })
      .join(' + ');
}
