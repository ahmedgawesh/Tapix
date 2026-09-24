import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../services/stock_alerts_pdf_service.dart';

/// Key used to store the last backup timestamp in SharedPreferences.
const _kLastBackupKey = 'last_backup_timestamp';

/// Number of days between backup reminders.
const _kBackupReminderDays = 3;

/// Key used to store dismissed notification IDs in SharedPreferences.
const _kDismissedNotificationsKey = 'dismissed_notifications';

/// Dashboard section that shows stock alerts (out of stock + low stock)
/// and a backup reminder. Uses Drift `.watch()` streams for realtime updates.
class StockAlertsSection extends StatefulWidget {
  const StockAlertsSection({super.key});

  @override
  State<StockAlertsSection> createState() => _StockAlertsSectionState();
}

class _StockAlertsSectionState extends State<StockAlertsSection> {
  late final AppDatabase _db;
  StreamSubscription<List<StockAlertItem>>? _outOfStockSub;
  StreamSubscription<List<StockAlertItem>>? _lowStockSub;
  List<StockAlertItem> _outOfStock = [];
  List<StockAlertItem> _lowStock = [];
  bool _showBackupReminder = false;
  bool _loadedOos = false;
  bool _loadedLow = false;
  Set<String> _dismissedNotifications = {};

  @override
  void initState() {
    super.initState();
    _db = sl<AppDatabase>();
    _loadDismissedNotifications();
    _subscribeOutOfStock();
    _subscribeLowStock();
    _checkBackupReminder();
  }

  @override
  void dispose() {
    _outOfStockSub?.cancel();
    _lowStockSub?.cancel();
    super.dispose();
  }

  // ─── realtime stream subscriptions ───

  void _subscribeOutOfStock() {
    _outOfStockSub = _db
        .customSelect(
          '''
      SELECT 
        p.id AS product_id,
        p.name AS product_name,
        COALESCE(v.sku, p.sku) AS variant_sku,
        COALESCE(v.barcode, p.barcode) AS variant_barcode,
        c.name AS category_name,
        pc.name AS color_name,
        pc.hex_code AS color_hex,
        sz.name AS size_name,
        COALESCE(v.stock_quantity, p.stock_quantity) AS current_stock,
        p.min_quantity AS reorder_level,
        COALESCE(v.cost_cents, p.cost_cents) AS cost_cents,
        COALESCE(v.price_cents, p.price_cents) AS price_cents
      FROM products p
      LEFT JOIN product_variants v ON v.product_id = p.id AND v.is_active = 1
      LEFT JOIN product_categories c ON c.id = p.category_id
      LEFT JOIN product_colors pc ON pc.id = v.color_id
      LEFT JOIN sizes sz ON sz.id = v.size_id
      WHERE p.is_active = 1
        AND p.track_inventory = 1
        AND COALESCE(v.stock_quantity, p.stock_quantity) <= 0
      ORDER BY p.name
      ''',
          readsFrom: {
            _db.products,
            _db.productVariants,
            _db.productCategories,
            _db.productColors,
            _db.sizes,
          },
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => StockAlertItem(
                  productId: row.read<int>('product_id'),
                  productName: row.read<String>('product_name'),
                  sku: row.readNullable<String>('variant_sku'),
                  barcode: row.readNullable<String>('variant_barcode'),
                  categoryName: row.readNullable<String>('category_name'),
                  colorName: row.readNullable<String>('color_name'),
                  colorHex: row.readNullable<String>('color_hex'),
                  sizeName: row.readNullable<String>('size_name'),
                  currentStock: row.read<int>('current_stock'),
                  reorderLevel: row.read<int>('reorder_level'),
                  costCents: row.read<int>('cost_cents'),
                  priceCents: row.read<int>('price_cents'),
                  isOutOfStock: true,
                ),
              )
              .toList(),
        )
        .listen((items) {
          if (mounted) {
            setState(() {
              _outOfStock = items;
              _loadedOos = true;
            });
          }
        });
  }

  void _subscribeLowStock() {
    _lowStockSub = _db
        .customSelect(
          '''
      SELECT 
        p.id AS product_id,
        p.name AS product_name,
        COALESCE(v.sku, p.sku) AS variant_sku,
        COALESCE(v.barcode, p.barcode) AS variant_barcode,
        c.name AS category_name,
        pc.name AS color_name,
        pc.hex_code AS color_hex,
        sz.name AS size_name,
        COALESCE(v.stock_quantity, p.stock_quantity) AS current_stock,
        p.min_quantity AS reorder_level,
        COALESCE(v.cost_cents, p.cost_cents) AS cost_cents,
        COALESCE(v.price_cents, p.price_cents) AS price_cents
      FROM products p
      LEFT JOIN product_variants v ON v.product_id = p.id AND v.is_active = 1
      LEFT JOIN product_categories c ON c.id = p.category_id
      LEFT JOIN product_colors pc ON pc.id = v.color_id
      LEFT JOIN sizes sz ON sz.id = v.size_id
      WHERE p.is_active = 1
        AND p.track_inventory = 1
        AND p.min_quantity > 0
        AND COALESCE(v.stock_quantity, p.stock_quantity) > 0
        AND COALESCE(v.stock_quantity, p.stock_quantity) <= p.min_quantity
      ORDER BY (p.min_quantity - COALESCE(v.stock_quantity, p.stock_quantity)) DESC
      ''',
          readsFrom: {
            _db.products,
            _db.productVariants,
            _db.productCategories,
            _db.productColors,
            _db.sizes,
          },
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => StockAlertItem(
                  productId: row.read<int>('product_id'),
                  productName: row.read<String>('product_name'),
                  sku: row.readNullable<String>('variant_sku'),
                  barcode: row.readNullable<String>('variant_barcode'),
                  categoryName: row.readNullable<String>('category_name'),
                  colorName: row.readNullable<String>('color_name'),
                  colorHex: row.readNullable<String>('color_hex'),
                  sizeName: row.readNullable<String>('size_name'),
                  currentStock: row.read<int>('current_stock'),
                  reorderLevel: row.read<int>('reorder_level'),
                  costCents: row.read<int>('cost_cents'),
                  priceCents: row.read<int>('price_cents'),
                  isOutOfStock: false,
                ),
              )
              .toList(),
        )
        .listen((items) {
          if (mounted) {
            setState(() {
              _lowStock = items;
              _loadedLow = true;
            });
          }
        });
  }

  // ─── dismissed notifications management ───

  Future<void> _loadDismissedNotifications() async {
    final prefs = sl<SharedPreferences>();
    final dismissed = prefs.getStringList(_kDismissedNotificationsKey) ?? [];
    if (mounted) setState(() => _dismissedNotifications = dismissed.toSet());
  }

  Future<void> _dismissNotification(String notificationId) async {
    final prefs = sl<SharedPreferences>();
    _dismissedNotifications.add(notificationId);
    await prefs.setStringList(
      _kDismissedNotificationsKey,
      _dismissedNotifications.toList(),
    );
    if (mounted) setState(() {});
  }

  String _getNotificationId(String type, int? productId) {
    if (type == 'backup') return 'backup_reminder';
    if (type == 'out_of_stock' && productId != null) return 'oos_$productId';
    if (type == 'low_stock' && productId != null) return 'low_$productId';
    return type;
  }

  List<StockAlertItem> _getVisibleItems(
    List<StockAlertItem> items,
    String type,
  ) {
    return items.where((item) {
      final id = _getNotificationId(type, item.productId);
      return !_dismissedNotifications.contains(id);
    }).toList();
  }

  // ─── backup reminder ───

  Future<void> _checkBackupReminder() async {
    final prefs = sl<SharedPreferences>();
    final lastBackupMs = prefs.getInt(_kLastBackupKey);
    if (lastBackupMs == null) {
      // Never backed up
      if (mounted) setState(() => _showBackupReminder = true);
      return;
    }
    final lastBackup = DateTime.fromMillisecondsSinceEpoch(lastBackupMs);
    final daysSince = DateTime.now().difference(lastBackup).inDays;
    if (daysSince >= _kBackupReminderDays) {
      if (mounted) setState(() => _showBackupReminder = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, settingsState) {
        final settings = settingsState.settings;

        // Check if notifications are enabled
        if (!settings.lowStockNotifications) {
          return const SizedBox.shrink();
        }

        if (!_loadedOos && !_loadedLow && !_showBackupReminder) {
          return const SizedBox.shrink();
        }

        // Filter out dismissed notifications
        final visibleOutOfStock = _getVisibleItems(_outOfStock, 'out_of_stock');
        final visibleLowStock = _getVisibleItems(_lowStock, 'low_stock');
        final showBackup =
            _showBackupReminder &&
            !_dismissedNotifications.contains('backup_reminder');

        final totalAlerts = visibleOutOfStock.length + visibleLowStock.length;
        final hasAnyNotification = totalAlerts > 0 || showBackup;
        if (!hasAnyNotification) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final badgeCount = totalAlerts + (showBackup ? 1 : 0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                Icon(LucideIcons.bell, size: 20, color: colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'dashboard.notifications'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Backup reminder card
            if (showBackup)
              Dismissible(
                key: const Key('backup_reminder'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) => _dismissNotification('backup_reminder'),
                background: _buildDismissBackground(
                  context,
                  Alignment.centerLeft,
                ),
                secondaryBackground: _buildDismissBackground(
                  context,
                  Alignment.centerRight,
                ),
                child: _BackupReminderCard(
                  onDismiss: () => _dismissNotification('backup_reminder'),
                ),
              ),

            if (showBackup && totalAlerts > 0) const SizedBox(height: 8),

            // Out of stock alert card
            if (visibleOutOfStock.isNotEmpty)
              Dismissible(
                key: const Key('out_of_stock_card'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) {
                  // Dismiss all out of stock items
                  for (final item in visibleOutOfStock) {
                    _dismissNotification(
                      _getNotificationId('out_of_stock', item.productId),
                    );
                  }
                },
                background: _buildDismissBackground(
                  context,
                  Alignment.centerLeft,
                ),
                secondaryBackground: _buildDismissBackground(
                  context,
                  Alignment.centerRight,
                ),
                child: _AlertCard(
                  icon: LucideIcons.packageX,
                  title: 'dashboard.out_of_stock'.tr(),
                  count: visibleOutOfStock.length,
                  color: colorScheme.error,
                  bgColor: isDark
                      ? colorScheme.error.withValues(alpha: 0.12)
                      : colorScheme.errorContainer.withValues(alpha: 0.5),
                  items: visibleOutOfStock,
                  onReportPressed: () => _generateReport(context),
                  onDismiss: () {
                    // Dismiss all out of stock items
                    for (final item in visibleOutOfStock) {
                      _dismissNotification(
                        _getNotificationId('out_of_stock', item.productId),
                      );
                    }
                  },
                ),
              ),

            if (visibleOutOfStock.isNotEmpty && visibleLowStock.isNotEmpty)
              const SizedBox(height: 8),

            // Low stock alert card
            if (visibleLowStock.isNotEmpty)
              Dismissible(
                key: const Key('low_stock_card'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) {
                  // Dismiss all low stock items
                  for (final item in visibleLowStock) {
                    _dismissNotification(
                      _getNotificationId('low_stock', item.productId),
                    );
                  }
                },
                background: _buildDismissBackground(
                  context,
                  Alignment.centerLeft,
                ),
                secondaryBackground: _buildDismissBackground(
                  context,
                  Alignment.centerRight,
                ),
                child: _AlertCard(
                  icon: LucideIcons.alertTriangle,
                  title: 'dashboard.low_stock'.tr(),
                  count: visibleLowStock.length,
                  color: Colors.orange,
                  bgColor: isDark
                      ? Colors.orange.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.08),
                  items: visibleLowStock,
                  onReportPressed: () => _generateReport(context),
                  onDismiss: () {
                    // Dismiss all low stock items
                    for (final item in visibleLowStock) {
                      _dismissNotification(
                        _getNotificationId('low_stock', item.productId),
                      );
                    }
                  },
                ),
              ),

            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildDismissBackground(BuildContext context, Alignment alignment) {
    final theme = Theme.of(context);
    final isLeft = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      padding: EdgeInsets.only(left: isLeft ? 20 : 0, right: isLeft ? 0 : 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        LucideIcons.trash2,
        color: theme.colorScheme.onErrorContainer,
      ),
    );
  }

  Future<void> _generateReport(BuildContext context) async {
    try {
      await StockAlertsPdfService.printReport(
        context: context,
        outOfStock: _outOfStock,
        lowStock: _lowStock,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('dashboard.report_error'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ─── Backup reminder card ───

class _BackupReminderCard extends StatelessWidget {
  final VoidCallback onDismiss;

  const _BackupReminderCard({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      color: isDark
          ? Colors.blue.withValues(alpha: 0.12)
          : Colors.blue.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(LucideIcons.hardDrive, size: 20, color: Colors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'dashboard.backup_reminder'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'dashboard.backup_reminder_desc'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.x, size: 16),
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              tooltip: 'common.dismiss'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Color color;
  final Color bgColor;
  final List<StockAlertItem> items;
  final VoidCallback onReportPressed;
  final VoidCallback onDismiss;

  const _AlertCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
    required this.bgColor,
    required this.items,
    required this.onReportPressed,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewItems = items.take(3).toList();

    return Card(
      elevation: 0,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$title ($count)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onReportPressed,
                  icon: const Icon(LucideIcons.fileText, size: 16),
                  label: Text('dashboard.report'.tr()),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'common.dismiss'.tr(),
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Preview items
            ...previewItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    if (item.colorHex != null && item.colorHex!.isNotEmpty) ...[
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _parseColor(item.colorHex!),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                            width: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        _itemLabel(item),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${item.currentStock}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (items.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'dashboard.and_more'.tr(args: ['${items.length - 3}']),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _itemLabel(StockAlertItem item) {
    final parts = <String>[item.productName];
    if (item.variantLabel.isNotEmpty) {
      parts.add('(${item.variantLabel})');
    }
    return parts.join(' ');
  }

  Color _parseColor(String hex) {
    try {
      final cleaned = hex.replaceAll('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }
}
