import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../data/services/company_profile_service.dart';
import '../../domain/entities/company_profile.dart';

class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _websiteController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _logoBase64;

  CompanyProfileService get _service => sl<CompanyProfileService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _service.getProfile();
    if (!mounted) return;

    _nameController.text = profile.name;
    _addressController.text = profile.address ?? '';
    _phoneController.text = profile.phone ?? '';
    _emailController.text = profile.email ?? '';
    _taxNumberController.text = profile.taxNumber ?? '';
    _websiteController.text = profile.website ?? '';
    _logoBase64 = profile.logoBase64;

    setState(() {
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taxNumberController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() {
      _saving = true;
    });

    try {
      final profile = CompanyProfile(
        name: _nameController.text.trim(),
        address: _emptyToNull(_addressController.text),
        phone: _emptyToNull(_phoneController.text),
        email: _emptyToNull(_emailController.text),
        taxNumber: _emptyToNull(_taxNumberController.text),
        website: _emptyToNull(_websiteController.text),
        logoBase64: _logoBase64,
      );

      await _service.saveProfile(profile);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('settings.company.saved'.tr())));

      if (context.canPop()) {
        context.pop();
      } else {
        context.pop();
      }
    } catch (e, st) {
      debugPrint('CompanyProfileScreen: failed to save company profile: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${'common.failed'.tr()}: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String? _emptyToNull(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _pickLogo() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) return;

      if (!mounted) return;
      setState(() {
        _logoBase64 = base64Encode(bytes);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${'common.failed'.tr()}: $e')));
    }
  }

  void _removeLogo() {
    setState(() {
      _logoBase64 = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
          tooltip: 'common.back'.tr(),
        ),
        title: Text('settings.company.title'.tr()),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Card with Logo
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // If screen is too small, use column layout
                          if (constraints.maxWidth < 360) {
                            return Column(
                              children: [
                                Center(
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: colorScheme
                                              .surfaceContainerHighest,
                                          gradient: _logoBase64 != null
                                              ? null
                                              : LinearGradient(
                                                  colors: [
                                                    colorScheme.primary
                                                        .withValues(alpha: 0.1),
                                                    colorScheme.primary
                                                        .withValues(alpha: 0.2),
                                                  ],
                                                ),
                                        ),
                                        child: ClipOval(
                                          child:
                                              (_logoBase64 == null ||
                                                  _logoBase64!.isEmpty)
                                              ? Icon(
                                                  LucideIcons.building2,
                                                  size: 40,
                                                  color: colorScheme.primary,
                                                )
                                              : Image.memory(
                                                  base64Decode(_logoBase64!),
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: colorScheme.surface,
                                              width: 2,
                                            ),
                                          ),
                                          child: InkWell(
                                            onTap: _pickLogo,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            child: Icon(
                                              LucideIcons.camera,
                                              size: 16,
                                              color: colorScheme.onPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'settings.company.logo'.tr(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: _pickLogo,
                                          icon: const Icon(
                                            LucideIcons.upload,
                                            size: 16,
                                          ),
                                          label: Text(
                                            'settings.company.choose_logo'.tr(),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                        if (!(_logoBase64 == null ||
                                            _logoBase64!.isEmpty))
                                          TextButton.icon(
                                            onPressed: _removeLogo,
                                            icon: const Icon(
                                              LucideIcons.trash2,
                                              size: 16,
                                            ),
                                            label: Text(
                                              'settings.company.remove_logo'
                                                  .tr(),
                                            ),
                                            style: TextButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }

                          // Normal row layout for larger screens
                          return Row(
                            children: [
                              Stack(
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          colorScheme.surfaceContainerHighest,
                                      gradient: _logoBase64 != null
                                          ? null
                                          : LinearGradient(
                                              colors: [
                                                colorScheme.primary.withValues(
                                                  alpha: 0.1,
                                                ),
                                                colorScheme.primary.withValues(
                                                  alpha: 0.2,
                                                ),
                                              ],
                                            ),
                                    ),
                                    child: ClipOval(
                                      child:
                                          (_logoBase64 == null ||
                                              _logoBase64!.isEmpty)
                                          ? Icon(
                                              LucideIcons.building2,
                                              size: 40,
                                              color: colorScheme.primary,
                                            )
                                          : Image.memory(
                                              base64Decode(_logoBase64!),
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colorScheme.surface,
                                          width: 2,
                                        ),
                                      ),
                                      child: InkWell(
                                        onTap: _pickLogo,
                                        borderRadius: BorderRadius.circular(14),
                                        child: Icon(
                                          LucideIcons.camera,
                                          size: 16,
                                          color: colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'settings.company.logo'.tr(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: _pickLogo,
                                          icon: const Icon(
                                            LucideIcons.upload,
                                            size: 16,
                                          ),
                                          label: Text(
                                            'settings.company.choose_logo'.tr(),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                        if (!(_logoBase64 == null ||
                                            _logoBase64!.isEmpty))
                                          TextButton.icon(
                                            onPressed: _removeLogo,
                                            icon: const Icon(
                                              LucideIcons.trash2,
                                              size: 16,
                                            ),
                                            label: Text(
                                              'settings.company.remove_logo'
                                                  .tr(),
                                            ),
                                            style: TextButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Company Information Section
                  _buildSectionHeader(
                    context,
                    icon: LucideIcons.building2,
                    title: 'settings.company.basic_info'.tr(),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: _nameController,
                              label: 'settings.company.name'.tr(),
                              icon: LucideIcons.building2,
                              validator: (value) {
                                final v = value?.trim() ?? '';
                                if (v.isEmpty) {
                                  return 'settings.company.name_required'.tr();
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _addressController,
                              label: 'settings.company.address'.tr(),
                              icon: LucideIcons.mapPin,
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _phoneController,
                              label: 'settings.company.phone'.tr(),
                              icon: LucideIcons.phone,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _emailController,
                              label: 'settings.company.email'.tr(),
                              icon: LucideIcons.mail,
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Additional Information Section
                  _buildSectionHeader(
                    context,
                    icon: LucideIcons.info,
                    title: 'settings.company.additional_info'.tr(),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildTextField(
                            controller: _taxNumberController,
                            label: 'settings.company.tax_number'.tr(),
                            icon: LucideIcons.fileText,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _websiteController,
                            label: 'settings.company.website'.tr(),
                            icon: LucideIcons.globe,
                            keyboardType: TextInputType.url,
                            onFieldSubmitted: (_) => _saving ? null : _save(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(LucideIcons.save),
                      label: Text(
                        _saving ? 'common.loading'.tr() : 'common.save'.tr(),
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int? maxLines = 1,
    String? Function(String?)? validator,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      textInputAction: (maxLines ?? 1) > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}
