import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_reset.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/database_health_check_service.dart';
import '../../../../core/utils/app_restart.dart';
import '../../../auth/data/services/owner_password_verification_service.dart';
import '../../../auth/data/services/session_service.dart';

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

      final passed = await DatabaseHealthCheckService(
        db,
      ).checkNullableVariantSku();
      if (!mounted) return;
      setState(() {
        _healthCheckResult = passed
            ? 'admin_tools.health_check_success'.tr()
            : 'admin_tools.health_check_failed'.tr();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _healthCheckResult = '${'admin_tools.health_check_failed'.tr()}: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _runningHealthCheck = false;
        });
      }
    }
  }

  Future<String?> _requestDeletionPassword() async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text('admin_tools.delete_confirm_title'.tr()),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('admin_tools.delete_confirm_body'.tr()),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'admin_tools.owner_password'.tr(),
                    errorText: error,
                  ),
                  onSubmitted: (_) {
                    if (controller.text.isEmpty) {
                      setDialogState(
                        () => error = 'admin_tools.owner_password_invalid'.tr(),
                      );
                    } else {
                      Navigator.pop(dialogContext, controller.text);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                if (controller.text.isEmpty) {
                  setDialogState(
                    () => error = 'admin_tools.owner_password_invalid'.tr(),
                  );
                } else {
                  Navigator.pop(dialogContext, controller.text);
                }
              },
              child: Text('admin_tools.delete_confirm_action'.tr()),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _deleteDatabase() async {
    if (_deletingDb) return;
    final password = await _requestDeletionPassword();
    if (password == null || !mounted) return;
    final verified = await sl<OwnerPasswordVerificationService>()
        .verifyCurrentOwner(password);
    if (!mounted) return;
    if (!verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('admin_tools.owner_password_invalid'.tr()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _deletingDb = true);
    try {
      final database = sl<AppDatabase>();
      await database.close();
      await DatabaseReset.deleteAllLocalDatabaseFiles();
      await sl<SessionService>().clearSession();
      await sl<SharedPreferences>().clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('admin_tools.delete_success'.tr())),
      );
      final closed = await closeAppForFreshRestart();
      if (!closed && mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text('admin_tools.restart_required_title'.tr()),
            content: Text('admin_tools.restart_required_body'.tr()),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('common.ok'.tr()),
              ),
            ],
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Database reset failed: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('admin_tools.delete_failed'.tr()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingDb = false);
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
