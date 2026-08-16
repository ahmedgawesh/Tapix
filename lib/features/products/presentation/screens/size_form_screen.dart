import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../domain/entities/size_entity.dart';
import '../bloc/sizes_bloc.dart';
import '../bloc/sizes_event.dart';

class SizeFormScreen extends StatelessWidget {
  final int? sizeId;
  final SizesBloc? bloc;

  const SizeFormScreen({super.key, this.sizeId, this.bloc});

  @override
  Widget build(BuildContext context) {
    final providedBloc = bloc;
    if (providedBloc != null) {
      providedBloc.add(const LoadSizes());
      return BlocProvider.value(
        value: providedBloc,
        child: _SizeFormView(sizeId: sizeId),
      );
    }

    return BlocProvider(
      create: (context) => sl<SizesBloc>()..add(const LoadSizes()),
      child: _SizeFormView(sizeId: sizeId),
    );
  }
}

class _SizeFormView extends StatefulWidget {
  final int? sizeId;

  const _SizeFormView({this.sizeId});

  @override
  State<_SizeFormView> createState() => _SizeFormViewState();
}

class _SizeFormViewState extends State<_SizeFormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sortOrderController = TextEditingController(text: '0');
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.sizeId != null) {
      _loadSize();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  Future<void> _loadSize() async {
    final bloc = context.read<SizesBloc>();
    final size = await bloc.repository.getSizeById(widget.sizeId!);
    if (size != null && mounted) {
      setState(() {
        _nameController.text = size.name;
        _descriptionController.text = size.description ?? '';
        _sortOrderController.text = size.sortOrder.toString();
        _isActive = size.isActive;
      });
    }
  }

  Future<void> _saveSize() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final bloc = context.read<SizesBloc>();
      final sortOrder = int.tryParse(_sortOrderController.text) ?? 0;

      if (widget.sizeId == null) {
        bloc.add(
          CreateSize(
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            sortOrder: sortOrder,
          ),
        );
      } else {
        final updatedSize = Size(
          id: widget.sizeId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          sortOrder: sortOrder,
          isActive: _isActive,
        );
        bloc.add(UpdateSize(updatedSize));
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.sizeId == null
                  ? 'sizes.size_created'.tr()
                  : 'sizes.size_updated'.tr(),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.sizeId == null
              ? 'sizes.add_size'.tr()
              : 'sizes.edit_size'.tr(),
        ),
        centerTitle: !isDesktop,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 600 : double.infinity,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'sizes.basic_info'.tr(),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'sizes.name'.tr(),
                                hintText: 'sizes.name_hint'.tr(),
                                prefixIcon: const Icon(LucideIcons.ruler),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'sizes.name_required'.tr();
                                }
                                if (value.trim().length > 50) {
                                  return 'sizes.name_too_long'.tr();
                                }
                                return null;
                              },
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _descriptionController,
                              decoration: InputDecoration(
                                labelText: 'sizes.description'.tr(),
                                hintText: 'sizes.description_hint'.tr(),
                                prefixIcon: const Icon(LucideIcons.fileText),
                                border: const OutlineInputBorder(),
                              ),
                              maxLines: 3,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _sortOrderController,
                              decoration: InputDecoration(
                                labelText: 'sizes.sort_order'.tr(),
                                hintText: 'sizes.sort_order_hint'.tr(),
                                prefixIcon: const Icon(LucideIcons.arrowUpDown),
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'sizes.sort_order_required'.tr();
                                }
                                final number = int.tryParse(value);
                                if (number == null || number < 0) {
                                  return 'sizes.sort_order_invalid'.tr();
                                }
                                return null;
                              },
                              onTap: () {
                                if (_sortOrderController.text == '0') {
                                  _sortOrderController.clear();
                                }
                              },
                              textInputAction: TextInputAction.done,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.sizeId != null)
                      Card(
                        child: SwitchListTile(
                          title: Text('sizes.active'.tr()),
                          subtitle: Text(
                            _isActive
                                ? 'sizes.active_description'.tr()
                                : 'sizes.inactive_description'.tr(),
                          ),
                          value: _isActive,
                          onChanged: (value) {
                            setState(() {
                              _isActive = value;
                            });
                          },
                          secondary: Icon(
                            _isActive
                                ? LucideIcons.checkCircle
                                : LucideIcons.xCircle,
                            color: _isActive
                                ? colorScheme.primary
                                : colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : () => context.pop(),
                            child: Text('sizes.cancel'.tr()),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _saveSize,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(LucideIcons.save),
                            label: Text('sizes.save'.tr()),
                          ),
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
    );
  }
}
