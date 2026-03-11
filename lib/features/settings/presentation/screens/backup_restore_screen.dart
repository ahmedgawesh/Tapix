import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/di/injection_container.dart';

/// Key used to store the last backup timestamp in SharedPreferences.
const _kLastBackupKey = 'last_backup_timestamp';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isBusy = false;
  String? _lastBackupLabel;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  void _loadLastBackup() {
    final prefs = sl<SharedPreferences>();
    final ms = prefs.getInt(_kLastBackupKey);
    if (ms != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      setState(() {
        _lastBackupLabel = DateFormat.yMMMd().add_jm().format(dt);
      });
    }
  }

  Future<String> _getDatabasePath() async {
    // Must match the path used in database_native.dart (getApplicationSupportDirectory)
    final dbFolder = await getApplicationSupportDirectory();
    return p.join(dbFolder.path, 'tapix.db');
  }

  // ─── Backup ───

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<String?> _getMobileBackupDir() async {
    if (Platform.isAndroid) {
      // Try the public Downloads folder first
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) return downloadsDir.path;
      // Fallback to external storage
      final extDirs = await getExternalStorageDirectories();
      if (extDirs != null && extDirs.isNotEmpty) return extDirs.first.path;
    }
    // iOS / fallback — use app documents directory
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  Future<void> _saveToDevice() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      final dbPath = await _getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        debugPrint('[Backup] Database file not found at: $dbPath');
        _showError('settings.backup.backup_error'.tr());
        return;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'tapix_backup_$timestamp.db';

      String destPath;

      if (_isMobile) {
        // On mobile, save directly to Downloads / external storage
        final dir = await _getMobileBackupDir();
        if (dir == null) {
          debugPrint('[Backup] Could not resolve mobile backup directory');
          _showError('settings.backup.backup_error'.tr());
          return;
        }
        destPath = p.join(dir, fileName);
      } else {
        // On desktop, let user pick a folder
        final dir = await FilePicker.platform.getDirectoryPath();
        if (dir == null) {
          // User cancelled
          setState(() => _isBusy = false);
          return;
        }
        destPath = p.join(dir, fileName);
      }

      await dbFile.copy(destPath);
      debugPrint('[Backup] Saved to: $destPath');

      await _recordBackupTimestamp();
      _showSuccess('settings.backup.backup_success'.tr());
    } catch (e, st) {
      debugPrint('[Backup] Error: $e\n$st');
      _showError('settings.backup.backup_error'.tr());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _shareBackup() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      final dbPath = await _getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        _showError('settings.backup.backup_error'.tr());
        return;
      }

      // Copy to temp with a timestamped name
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final tempPath = p.join(tempDir.path, 'tapix_backup_$timestamp.db');
      await dbFile.copy(tempPath);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempPath)],
          text: 'Tapix Backup - $timestamp',
        ),
      );

      await _recordBackupTimestamp();
      _showSuccess('settings.backup.backup_success'.tr());
    } catch (e, st) {
      debugPrint('[Backup:Share] Error: $e\n$st');
      _showError('settings.backup.backup_error'.tr());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ─── Restore ───

  Future<void> _restoreFromFile() async {
    if (_isBusy) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final pickedPath = result.files.single.path;
    if (pickedPath == null) return;

    // Validate it looks like a SQLite file
    final pickedFile = File(pickedPath);
    final bytes = await pickedFile.readAsBytes();
    if (bytes.length < 16 ||
        String.fromCharCodes(bytes.sublist(0, 15)) != 'SQLite format 3') {
      if (mounted) _showError('settings.backup.invalid_file'.tr());
      return;
    }

    if (!mounted) return;

    // Confirm with user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(LucideIcons.alertTriangle, color: colorScheme.error, size: 32),
          title: Text('settings.backup.restore_warning_title'.tr()),
          content: Text('settings.backup.restore_warning_body'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('settings.backup.restore_confirm'.tr()),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);

    try {
      final dbPath = await _getDatabasePath();

      // Overwrite the database file
      await pickedFile.copy(dbPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('settings.backup.restore_success'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Give time for snackbar to show, then exit the app so it restarts fresh
      await Future<void>.delayed(const Duration(seconds: 2));
      exit(0);
    } catch (e, st) {
      debugPrint('[Backup:Restore] Error: $e\n$st');
      _showError('settings.backup.restore_error'.tr());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ─── Helpers ───

  Future<void> _recordBackupTimestamp() async {
    final prefs = sl<SharedPreferences>();
    final now = DateTime.now();
    await prefs.setInt(_kLastBackupKey, now.millisecondsSinceEpoch);
    if (mounted) {
      setState(() {
        _lastBackupLabel = DateFormat.yMMMd().add_jm().format(now);
      });
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.backup.section_title'.tr()),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Info card
              Card(
                elevation: 0,
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.info, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'settings.backup.backup_info'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Last backup status
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        _lastBackupLabel != null
                            ? LucideIcons.checkCircle
                            : LucideIcons.alertCircle,
                        color: _lastBackupLabel != null
                            ? Colors.green
                            : colorScheme.error,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _lastBackupLabel != null
                              ? 'settings.backup.last_backup'.tr(args: [_lastBackupLabel!])
                              : 'settings.backup.never_backed_up'.tr(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Create Backup section
              Text(
                'settings.backup.create_backup'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              _ActionTile(
                icon: LucideIcons.hardDrive,
                title: 'settings.backup.save_to_device'.tr(),
                color: Colors.blue,
                onTap: _isBusy ? null : _saveToDevice,
              ),
              const SizedBox(height: 8),
              _ActionTile(
                icon: LucideIcons.share2,
                title: 'settings.backup.share_backup'.tr(),
                color: Colors.green,
                onTap: _isBusy ? null : _shareBackup,
              ),
              const SizedBox(height: 24),

              // Restore section
              Text(
                'settings.backup.restore_backup'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              _ActionTile(
                icon: LucideIcons.folderInput,
                title: 'settings.backup.restore_from_file'.tr(),
                color: Colors.orange,
                onTap: _isBusy ? null : _restoreFromFile,
              ),
              const SizedBox(height: 24),

              // Tip card
              Card(
                elevation: 0,
                color: Colors.amber.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(LucideIcons.lightbulb, size: 20, color: Colors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'settings.backup.backup_tip'.tr(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Loading overlay
          if (_isBusy)
            Container(
              color: Colors.black26,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'settings.backup.creating_backup'.tr(),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      color: isDark
          ? color.withValues(alpha: 0.12)
          : color.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Icon(LucideIcons.chevronRight, color: color, size: 20),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
