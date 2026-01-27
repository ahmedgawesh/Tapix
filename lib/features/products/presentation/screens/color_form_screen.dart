import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../data/models/product_color_model.dart';
import '../bloc/colors_bloc.dart';

class ColorFormScreen extends StatefulWidget {
  final int? colorId;

  const ColorFormScreen({
    super.key,
    this.colorId,
  });

  @override
  State<ColorFormScreen> createState() => _ColorFormScreenState();
}

class _ColorFormScreenState extends State<ColorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hexCodeController = TextEditingController();
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.colorId != null) {
      _loadColor();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hexCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadColor() async {
    setState(() => _isLoading = true);
    try {
      final bloc = sl<ColorsBloc>();
      final colors = await bloc.repository.getAllColors();
      final color = colors.firstWhere(
        (c) => c.id == widget.colorId,
        orElse: () => throw Exception('colors.form.error_color_not_found'.tr()),
      );
      if (mounted) {
        setState(() {
          _nameController.text = color.name;
          _hexCodeController.text = color.hexCode ?? '';
          _isActive = color.isActive;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('colors.form.error_loading_color'.tr(args: [e.toString()])),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _validateHexCode(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final hexPattern = RegExp(r'^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})$');
    if (!hexPattern.hasMatch(value)) {
      return 'colors.form.validation_invalid_hex'.tr();
    }

    return null;
  }

  void _onColorPicked(Color color) {
    final argb = color.toARGB32();
    final hexCode = '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    setState(() {
      _hexCodeController.text = hexCode;
    });
  }

  void _showColorPicker() {
    Color? previewColor;
    final hexText = _hexCodeController.text.trim();
    if (hexText.isNotEmpty && _validateHexCode(hexText) == null) {
      try {
        final hexString = hexText.replaceAll('#', '');
        previewColor = Color(int.parse('FF$hexString', radix: 16));
      } catch (e) {
        previewColor = Colors.blue;
      }
    } else {
      previewColor = Colors.blue;
    }

    showDialog<Color>(
      context: context,
      builder: (context) => _SimpleColorPickerDialog(
        initialColor: previewColor!,
        onColorSelected: (color) {
          _onColorPicked(color);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _saveColor() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final bloc = context.read<ColorsBloc>();

      String hexCode = _hexCodeController.text.trim();
      if (hexCode.isNotEmpty && !hexCode.startsWith('#')) {
        hexCode = '#$hexCode';
      }

      final sanitizedHex = hexCode.isEmpty ? null : hexCode;

      if (widget.colorId == null) {
        final model = ProductColorModel(
          id: 0,
          name: _nameController.text.trim(),
          hexCode: sanitizedHex,
          isActive: true,
        );
        await bloc.repository.createColor(model);
      } else {
        final updatedColor = ProductColorModel(
          id: widget.colorId!,
          name: _nameController.text.trim(),
          hexCode: sanitizedHex,
          isActive: _isActive,
        );
        final success = await bloc.repository.updateColor(updatedColor);
        if (!success) {
          throw Exception('colors.form.error_update_failed'.tr());
        }
      }

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.colorId == null
                  ? 'colors.form.success_created'.tr()
                  : 'colors.form.success_updated'.tr(),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('colors.form.error_saving_color'.tr(args: [e.toString()])),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    Color? previewColor;
    final hexText = _hexCodeController.text.trim();
    if (hexText.isNotEmpty && _validateHexCode(hexText) == null) {
      try {
        final hexString = hexText.replaceAll('#', '');
        previewColor = Color(int.parse('FF$hexString', radix: 16));
      } catch (e) {
        previewColor = null;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.colorId == null
              ? 'colors.add_color'.tr()
              : 'colors.edit_color'.tr(),
        ),
        centerTitle: !isDesktop,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isDesktop ? 600 : double.infinity,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (previewColor != null) ...[
                            Center(
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: previewColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: colorScheme.outline.withValues(alpha: 0.3),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'colors.name'.tr(),
                              hintText: 'colors.form.name_hint'.tr(),
                              prefixIcon: const Icon(LucideIcons.tag),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'colors.form.validation_name_required'.tr();
                              }
                              if (value.trim().length > 50) {
                                return 'colors.form.validation_name_max'.tr();
                              }
                              return null;
                            },
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _hexCodeController,
                            decoration: InputDecoration(
                              labelText: 'colors.hex_code'.tr(),
                              hintText: '#FF0000 or #F00',
                              prefixIcon: const Icon(LucideIcons.hash),
                              suffixIcon: IconButton(
                                icon: const Icon(LucideIcons.palette),
                                onPressed: _showColorPicker,
                                tooltip: 'colors.form.pick_color'.tr(),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: _validateHexCode,
                            onChanged: (value) {
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 16),
                          if (widget.colorId != null) ...[
                            SwitchListTile(
                              title: Text('colors.active'.tr()),
                              subtitle: Text(
                                _isActive
                                    ? 'colors.form.active_hint'.tr()
                                    : 'colors.form.inactive_hint'.tr(),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                              ),
                              value: _isActive,
                              onChanged: (value) {
                                setState(() => _isActive = value);
                              },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: colorScheme.outline.withValues(alpha: 0.2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ] else
                            const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isLoading ? null : () => context.pop(),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text('colors.cancel'.tr()),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _isLoading ? null : _saveColor,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text('colors.save'.tr()),
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

class _SimpleColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorSelected;

  const _SimpleColorPickerDialog({
    required this.initialColor,
    required this.onColorSelected,
  });

  @override
  State<_SimpleColorPickerDialog> createState() => _SimpleColorPickerDialogState();
}

class _SimpleColorPickerDialogState extends State<_SimpleColorPickerDialog> {
  late Color _selectedColor;

  final List<Color> _commonColors = [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.grey,
    Colors.blueGrey,
    Colors.black,
    Colors.white,
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('colors.picker.title'.tr()),
      content: SizedBox(
        width: 300,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _commonColors.length,
          itemBuilder: (context, index) {
            final color = _commonColors[index];
            final isSelected = _selectedColor == color;
            
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedColor = color;
                });
                widget.onColorSelected(color);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.grey.shade300,
                    width: isSelected ? 3 : 1,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
      ],
    );
  }
}
