import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/desktop_license_service.dart';

class DesktopLicenseGate extends StatefulWidget {
  final DesktopLicenseService service;
  final Widget child;

  const DesktopLicenseGate({
    super.key,
    required this.service,
    required this.child,
  });

  @override
  State<DesktopLicenseGate> createState() => _DesktopLicenseGateState();
}

class _DesktopLicenseGateState extends State<DesktopLicenseGate> {
  final _keyController = TextEditingController();
  bool _submitting = false;
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_changed);
    widget.service.initialize().then((status) {
      if (status == DesktopLicenseStatus.valid &&
          widget.service.needsOnlineRefresh) {
        widget.service.refreshOnline();
      }
    });
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    _keyController.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _activate() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errorCode = null;
    });
    final result = await widget.service.activate(_keyController.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _errorCode = result.errorCode;
    });
  }

  Future<void> _refresh() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorCode = null;
    });
    final result = await widget.service.refreshOnline();
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _errorCode = result.errorCode;
    });
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.isSupported || widget.service.isActivated) {
      return widget.child;
    }
    final status = widget.service.status;
    if (status == DesktopLicenseStatus.checking ||
        status == DesktopLicenseStatus.notApplicable) {
      return const ColoredBox(
        color: Colors.transparent,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final copy = _DesktopLicenseCopy.forLanguage(context.locale.languageCode);
    final canRefresh =
        status == DesktopLicenseStatus.offlineLeaseExpired ||
        status == DesktopLicenseStatus.revoked;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                elevation: 8,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 58,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        copy.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Text(copy.subtitle, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      if (_statusText(status, copy) case final text?)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(text),
                        ),
                      if (_errorText(_errorCode, copy) case final error?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      TextField(
                        controller: _keyController,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: copy.licenseKey,
                          hintText: 'TBX-XXXX-XXXX-XXXX-XXXX-XXXX',
                          prefixIcon: const Icon(Icons.key_outlined),
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _activate(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _activate,
                        icon: _submitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_open_outlined),
                        label: Text(copy.activate),
                      ),
                      if (canRefresh) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _submitting ? null : _refresh,
                          icon: const Icon(Icons.sync),
                          label: Text(copy.recheck),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        copy.internetNote,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                _open(DesktopLicenseService.manageLicenseUrl),
                            icon: const Icon(Icons.devices_outlined),
                            label: Text(copy.manageDevices),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _open(DesktopLicenseService.buyLicenseUrl),
                            icon: const Icon(Icons.shopping_cart_outlined),
                            label: Text(copy.buyLicense),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _statusText(DesktopLicenseStatus status, _DesktopLicenseCopy copy) {
    switch (status) {
      case DesktopLicenseStatus.missing:
        return null;
      case DesktopLicenseStatus.offlineLeaseExpired:
        return copy.onlineCheckRequired;
      case DesktopLicenseStatus.revoked:
        return copy.revoked;
      case DesktopLicenseStatus.deviceMismatch:
        return copy.deviceMismatch;
      case DesktopLicenseStatus.invalidSignature:
      case DesktopLicenseStatus.malformed:
      case DesktopLicenseStatus.clockRollback:
        return copy.invalidLocalLicense;
      case DesktopLicenseStatus.invalidProduct:
      case DesktopLicenseStatus.platformMismatch:
        return copy.invalidProduct;
      case DesktopLicenseStatus.expired:
        return copy.expired;
      case DesktopLicenseStatus.notApplicable:
      case DesktopLicenseStatus.checking:
      case DesktopLicenseStatus.valid:
        return null;
    }
  }

  String? _errorText(String? code, _DesktopLicenseCopy copy) {
    switch (code) {
      case null:
        return null;
      case 'invalid_key_format':
      case 'invalid_license':
        return copy.invalidKey;
      case 'device_limit_reached':
        return copy.deviceLimit;
      case 'network_error':
        return copy.networkError;
      case 'rate_limited':
        return copy.rateLimited;
      case 'invalid_product':
        return copy.invalidProduct;
      case 'license_revoked':
      case 'device_not_active':
        return copy.revoked;
      default:
        return copy.activationFailed;
    }
  }
}

class _DesktopLicenseCopy {
  final String title;
  final String subtitle;
  final String licenseKey;
  final String activate;
  final String recheck;
  final String internetNote;
  final String manageDevices;
  final String buyLicense;
  final String invalidKey;
  final String deviceLimit;
  final String networkError;
  final String rateLimited;
  final String invalidLocalLicense;
  final String deviceMismatch;
  final String invalidProduct;
  final String expired;
  final String revoked;
  final String onlineCheckRequired;
  final String activationFailed;

  const _DesktopLicenseCopy({
    required this.title,
    required this.subtitle,
    required this.licenseKey,
    required this.activate,
    required this.recheck,
    required this.internetNote,
    required this.manageDevices,
    required this.buyLicense,
    required this.invalidKey,
    required this.deviceLimit,
    required this.networkError,
    required this.rateLimited,
    required this.invalidLocalLicense,
    required this.deviceMismatch,
    required this.invalidProduct,
    required this.expired,
    required this.revoked,
    required this.onlineCheckRequired,
    required this.activationFailed,
  });

  static _DesktopLicenseCopy forLanguage(String language) {
    if (language == 'ar') {
      return const _DesktopLicenseCopy(
        title: 'تفعيل TapBix على الكمبيوتر',
        subtitle:
            'أدخل مفتاح الترخيص لتفعيل هذا الجهاز بنظام Windows أو Linux.',
        licenseKey: 'مفتاح الترخيص',
        activate: 'تفعيل TapBix',
        recheck: 'التحقق عبر الإنترنت',
        internetNote:
            'يحتاج التفعيل الأول إلى الإنترنت، ثم يعمل البرنامج دون اتصال مع تحقق أمني دوري.',
        manageDevices: 'إدارة الأجهزة',
        buyLicense: 'شراء ترخيص',
        invalidKey: 'مفتاح الترخيص غير صحيح.',
        deviceLimit:
            'تم بلوغ حد الأجهزة. ألغِ الجهاز القديم من حسابك على الموقع أولًا.',
        networkError: 'تعذر الاتصال بخادم التفعيل.',
        rateLimited: 'محاولات كثيرة؛ انتظر قليلًا ثم حاول مرة أخرى.',
        invalidLocalLicense: 'ملف الترخيص غير صالح أو تم العبث به.',
        deviceMismatch: 'هذا الترخيص المحفوظ يخص جهازًا مختلفًا.',
        invalidProduct: 'هذا المفتاح غير صالح لنظام التشغيل الحالي.',
        expired: 'انتهت صلاحية هذا الترخيص.',
        revoked: 'تم إلغاء هذا الجهاز أو الترخيص من الموقع.',
        onlineCheckRequired:
            'انتهت فترة العمل دون اتصال. اتصل بالإنترنت للتحقق من الترخيص.',
        activationFailed: 'تعذر إتمام التفعيل. حاول مرة أخرى.',
      );
    }
    return const _DesktopLicenseCopy(
      title: 'Activate TapBix Desktop',
      subtitle:
          'Enter your license key to activate this Windows or Linux device.',
      licenseKey: 'License key',
      activate: 'Activate TapBix',
      recheck: 'Check online',
      internetNote:
          'Internet is required for first activation, followed by periodic security validation.',
      manageDevices: 'Manage devices',
      buyLicense: 'Buy a license',
      invalidKey: 'The license key is invalid.',
      deviceLimit: 'The device limit has been reached.',
      networkError: 'Could not reach the activation server.',
      rateLimited: 'Too many attempts. Try again later.',
      invalidLocalLicense: 'The local license is invalid or was modified.',
      deviceMismatch: 'The stored license belongs to another device.',
      invalidProduct: 'This license is not valid for this operating system.',
      expired: 'This license has expired.',
      revoked: 'This device or license was revoked.',
      onlineCheckRequired: 'Connect to the internet to validate this license.',
      activationFailed: 'Activation failed. Try again.',
    );
  }
}
