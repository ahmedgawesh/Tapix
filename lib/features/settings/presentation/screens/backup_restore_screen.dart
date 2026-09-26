import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/backup/database_backup_service.dart';
import '../../../../core/utils/app_restart.dart';

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
        _lastBackupLabel = DateFormat('dd/MM/yyyy').add_jm().format(dt);
      });
    }
  }

  DatabaseBackupService get _backupService => DatabaseBackupService();

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<String?> _getMobileBackupDir() async {
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) return downloads.path;
      final external = await getExternalStorageDirectories();
      if (external != null && external.isNotEmpty) return external.first.path;
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  Future<String?> _portablePassphrase() async {
    if (!await _backupService.activeDatabaseIsEncrypted) return null;
    if (!mounted) return null;
    return _askForPassphrase(confirm: true);
  }

  Future<void> _saveToDevice() async {
    if (_isBusy) return;
    final encrypted = await _backupService.activeDatabaseIsEncrypted;
    final passphrase = encrypted ? await _portablePassphrase() : null;
    if (encrypted && passphrase == null) return;
    if (!mounted) return;
    setState(() => _isBusy = true);
    try {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'tapix_backup_$timestamp.db';
      final String destination;
      if (_isMobile) {
        final directory = await _getMobileBackupDir();
        if (directory == null) throw const InvalidTapixBackupException();
        destination = p.join(directory, fileName);
      } else {
        final directory = await FilePicker.getDirectoryPath();
        if (directory == null) return;
        destination = p.join(directory, fileName);
      }
      await _backupService.createPortableBackup(
        destination: File(destination),
        passphrase: passphrase,
      );
      await _recordBackupTimestamp();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('settings.backup.backup_success'.tr()),
                const SizedBox(height: 4),
                Text(
                  destination,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[Backup] Error: $error\n$stackTrace');
      _showError(_backupErrorMessage(error, restoring: false));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _shareBackup() async {
    if (_isBusy) return;
    final encrypted = await _backupService.activeDatabaseIsEncrypted;
    final passphrase = encrypted ? await _portablePassphrase() : null;
    if (encrypted && passphrase == null) return;
    if (!mounted) return;
    setState(() => _isBusy = true);
    try {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final temporaryDirectory = await getTemporaryDirectory();
      final backup = await _backupService.createPortableBackup(
        destination: File(
          p.join(temporaryDirectory.path, 'tapix_backup_$timestamp.db'),
        ),
        passphrase: passphrase,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backup.path)],
          text: 'TapBix Backup - $timestamp',
        ),
      );
      await _recordBackupTimestamp();
      _showSuccess('settings.backup.backup_success'.tr());
    } catch (error, stackTrace) {
      debugPrint('[Backup:Share] Error: $error\n$stackTrace');
      _showError(_backupErrorMessage(error, restoring: false));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _restoreFromFile() async {
    if (_isBusy) return;
    final selected = await FilePicker.pickFile(type: FileType.any);
    if (selected == null || !mounted) return;

    final ownsTemporarySelection = selected.path == null;
    final selectedFile = ownsTemporarySelection
        ? await _copyPickedFileToTemporary(selected)
        : File(selected.path!);
    try {
      final isPlain = await DatabaseBackupService.isPlainSqliteFile(
        selectedFile,
      );
      final passphrase = isPlain
          ? null
          : await _askForPassphrase(confirm: false);
      if (!isPlain && passphrase == null) return;
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            LucideIcons.alertTriangle,
            color: Theme.of(dialogContext).colorScheme.error,
          ),
          title: Text('settings.backup.restore_warning_title'.tr()),
          content: Text('settings.backup.restore_warning_body'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('settings.backup.restore_confirm'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _isBusy = true);
      try {
        final database = sl<AppDatabase>();
        await _backupService.restorePortableBackup(
          backup: selectedFile,
          passphrase: passphrase,
          currentSchemaVersion: database.schemaVersion,
          closeDatabase: database.close,
        );
        if (!mounted) return;
        _showSuccess('settings.backup.restore_success'.tr());
        final closed = await closeAppForFreshRestart();
        if (!closed && mounted) await _showManualRestartDialog();
      } catch (error, stackTrace) {
        debugPrint('[Backup:Restore] Error: $error\n$stackTrace');
        _showError(_backupErrorMessage(error, restoring: true));
      } finally {
        if (mounted) setState(() => _isBusy = false);
      }
    } finally {
      if (ownsTemporarySelection && await selectedFile.exists()) {
        await selectedFile.delete();
      }
    }
  }

  Future<File> _copyPickedFileToTemporary(PlatformFile selected) async {
    final directory = await getTemporaryDirectory();
    final target = File(
      p.join(
        directory.path,
        'tapix_restore_${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await target.writeAsBytes(await selected.readAsBytes(), flush: true);
    return target;
  }

  Future<String?> _askForPassphrase({required bool confirm}) async {
    final valueController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(LucideIcons.lockKeyhole),
          title: Text(
            (confirm
                    ? 'settings.backup.passphrase_create_title'
                    : 'settings.backup.passphrase_enter_title')
                .tr(),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('settings.backup.passphrase_help'.tr()),
                const SizedBox(height: 12),
                TextField(
                  controller: valueController,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'settings.backup.passphrase'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (confirm) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'settings.backup.passphrase_confirm'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                final value = valueController.text;
                if (value.length <
                    DatabaseBackupService.minimumPassphraseLength) {
                  setDialogState(
                    () => error = 'settings.backup.passphrase_too_short'.tr(),
                  );
                } else if (confirm && value != confirmController.text) {
                  setDialogState(
                    () => error = 'settings.backup.passphrase_mismatch'.tr(),
                  );
                } else {
                  Navigator.pop(dialogContext, value);
                }
              },
              child: Text('common.confirm'.tr()),
            ),
          ],
        ),
      ),
    );
    valueController.dispose();
    confirmController.dispose();
    return result;
  }

  String _backupErrorMessage(Object error, {required bool restoring}) {
    return switch (error) {
      BackupPassphraseRequiredException() =>
        'settings.backup.passphrase_required'.tr(),
      BackupPassphraseInvalidException() =>
        'settings.backup.passphrase_invalid'.tr(),
      BackupFromNewerVersionException() => 'settings.backup.newer_version'.tr(),
      InvalidTapixBackupException() => 'settings.backup.invalid_file'.tr(),
      _ =>
        (restoring
                ? 'settings.backup.restore_error'
                : 'settings.backup.backup_error')
            .tr(),
    };
  }

  Future<void> _showManualRestartDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(LucideIcons.refreshCw),
        title: Text('settings.backup.restart_required_title'.tr()),
        content: Text('settings.backup.restart_required_body'.tr()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───

  Future<void> _recordBackupTimestamp() async {
    final prefs = sl<SharedPreferences>();
    final now = DateTime.now();
    await prefs.setInt(_kLastBackupKey, now.millisecondsSinceEpoch);
    if (mounted) {
      setState(() {
        _lastBackupLabel = DateFormat('dd/MM/yyyy').add_jm().format(now);
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
                      Icon(
                        LucideIcons.info,
                        size: 20,
                        color: colorScheme.primary,
                      ),
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
                              ? 'settings.backup.last_backup'.tr(
                                  args: [_lastBackupLabel!],
                                )
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
                      const Icon(
                        LucideIcons.lightbulb,
                        size: 20,
                        color: Colors.amber,
                      ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
