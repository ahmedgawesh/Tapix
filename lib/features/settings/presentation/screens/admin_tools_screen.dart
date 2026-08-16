import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_reset.dart';
import '../../../../core/di/injection_container.dart';

class AdminToolsScreen extends StatefulWidget {
  const AdminToolsScreen({super.key});

  @override
  State<AdminToolsScreen> createState() => _AdminToolsScreenState();
}

class _AdminToolsScreenState extends State<AdminToolsScreen> {
  String? _dbLocation;
  String? _healthCheckResult;
  bool _runningHealthCheck = false;
  bool _deletingDb = false;

  @override
  void initState() {
    super.initState();
    _loadDbLocation();
  }

  Future<void> _loadDbLocation() async {
    final loc = await DatabaseReset.getDatabaseLocation();
    if (!mounted) return;
    setState(() {
      _dbLocation = loc;
    });
  }

  Future<void> _runHealthCheck() async {
    setState(() {
      _runningHealthCheck = true;
      _healthCheckResult = null;
    });

    try {
      final db = sl<AppDatabase>();

      final currency = await (db.select(db.currencies)..limit(1)).getSingle();

      final now = DateTime.now().millisecondsSinceEpoch;
      final sku = 'HC-$now';

      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              sku: Value<String?>(sku),
              name: 'Health Check Product',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              currencyId: Value(currency.id),
            ),
          );

      final variantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion(
              productId: Value(productId),
              sku: const Value<String?>(null),
              barcode: const Value<String?>(null),
              colorId: const Value<int?>(null),
              sizeId: const Value<int?>(null),
              costCents: Value(Decimal.fromInt(100)),
              priceCents: Value(Decimal.fromInt(200)),
              priceAdjustmentCents: Value(Decimal.zero),
              stockQuantity: const Value(1),
              isActive: const Value(true),
            ),
          );

      final variant =
          await (db.select(db.productVariants)
                ..where((v) => v.id.equals(variantId))
                ..limit(1))
              .getSingle();

      await (db.delete(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).go();
      await (db.delete(db.products)..where((p) => p.id.equals(productId))).go();

      final passed = variant.sku == null;

      setState(() {
        _healthCheckResult = passed
            ? 'OK: Inserted product + variant with NULL sku successfully.'
            : 'FAILED: Variant sku was not NULL after insert.';
      });
    } catch (e) {
      setState(() {
        _healthCheckResult = 'FAILED: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _runningHealthCheck = false;
        });
      }
    }
  }

  Future<void> _deleteDatabase() async {
    setState(() {
      _deletingDb = true;
    });

    try {
      final prefs = sl<SharedPreferences>();
      await prefs.clear();

      final db = sl<AppDatabase>();
      await db.close();

      final deleted = await DatabaseReset.deleteDatabaseFile();

      if (!mounted) return;

      final msg = deleted
          ? 'admin_tools.delete_success'.tr()
          : 'admin_tools.delete_not_found'.tr();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${'common.failed'.tr()}: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _deletingDb = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/settings');
            }
          },
          tooltip: 'common.back'.tr(),
        ),
        title: Text('admin_tools.title'.tr()),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'database'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${'admin_tools.location'.tr()}: ${_dbLocation ?? 'common.loading'.tr()}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${'admin_tools.schema_version'.tr()}: ${sl<AppDatabase>().schemaVersion}',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _deletingDb ? null : _deleteDatabase,
                    child: Text(
                      _deletingDb
                          ? 'admin_tools.deleting'.tr()
                          : 'admin_tools.delete_reset'.tr(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'admin_tools.delete_warning'.tr(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'health_check'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _runningHealthCheck ? null : _runHealthCheck,
                    child: Text(
                      _runningHealthCheck
                          ? 'Running...'
                          : 'Run DB Health Check',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_healthCheckResult != null)
                    Text(
                      _healthCheckResult!,
                      style: TextStyle(
                        color: (_healthCheckResult?.startsWith('OK') ?? false)
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
