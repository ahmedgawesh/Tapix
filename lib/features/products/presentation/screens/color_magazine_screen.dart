import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ColorMagazineScreen extends StatefulWidget {
  const ColorMagazineScreen({super.key});

  @override
  State<ColorMagazineScreen> createState() => _ColorMagazineScreenState();
}

class _ColorMagazineScreenState extends State<ColorMagazineScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const List<Map<String, String>> _colors = [
    {'name': 'Red', 'hex': '#FF0000'},
    {'name': 'Green', 'hex': '#00FF00'},
    {'name': 'Blue', 'hex': '#0000FF'},
    {'name': 'Yellow', 'hex': '#FFFF00'},
    {'name': 'Cyan', 'hex': '#00FFFF'},
    {'name': 'Magenta', 'hex': '#FF00FF'},
    {'name': 'Orange', 'hex': '#FFA500'},
    {'name': 'Purple', 'hex': '#800080'},
    {'name': 'Pink', 'hex': '#FFC0CB'},
    {'name': 'Brown', 'hex': '#964B00'},
    {'name': 'Gray', 'hex': '#808080'},
    {'name': 'Black', 'hex': '#000000'},
    {'name': 'White', 'hex': '#FFFFFF'},
    {'name': 'Navy', 'hex': '#000080'},
    {'name': 'Teal', 'hex': '#008080'},
    {'name': 'Olive', 'hex': '#808000'},
    {'name': 'Maroon', 'hex': '#800000'},
    {'name': 'Gold', 'hex': '#FFD700'},
    {'name': 'Silver', 'hex': '#C0C0C0'},
    {'name': 'Coral', 'hex': '#FF7F50'},
    {'name': 'Salmon', 'hex': '#FA8072'},
    {'name': 'Sky Blue', 'hex': '#87CEEB'},
    {'name': 'Royal Blue', 'hex': '#4169E1'},
    {'name': 'Indigo', 'hex': '#4B0082'},
    {'name': 'Violet', 'hex': '#EE82EE'},
    {'name': 'Lime', 'hex': '#BFFF00'},
    {'name': 'Mint', 'hex': '#98FF98'},
    {'name': 'Turquoise', 'hex': '#40E0D0'},
    {'name': 'Beige', 'hex': '#F5F5DC'},
    {'name': 'Ivory', 'hex': '#FFFFF0'},
    {'name': 'Khaki', 'hex': '#F0E68C'},
    {'name': 'Chocolate', 'hex': '#D2691E'},
    {'name': 'Crimson', 'hex': '#DC143C'},
    {'name': 'Tomato', 'hex': '#FF6347'},
    {'name': 'Plum', 'hex': '#DDA0DD'},
    {'name': 'Orchid', 'hex': '#DA70D6'},
    {'name': 'Lavender', 'hex': '#E6E6FA'},
    {'name': 'Azure', 'hex': '#F0FFFF'},
    {'name': 'Aqua', 'hex': '#00FFFF'},
    {'name': 'Forest Green', 'hex': '#228B22'},
    {'name': 'Sea Green', 'hex': '#2E8B57'},
    {'name': 'Steel Blue', 'hex': '#4682B4'},
    {'name': 'Slate Gray', 'hex': '#708090'},
    {'name': 'Dim Gray', 'hex': '#696969'},
    {'name': 'Gainsboro', 'hex': '#DCDCDC'},
    {'name': 'Firebrick', 'hex': '#B22222'},
    {'name': 'Sienna', 'hex': '#A0522D'},
    {'name': 'Peru', 'hex': '#CD853F'},
    {'name': 'Wheat', 'hex': '#F5DEB3'},
    {'name': 'Tan', 'hex': '#D2B48C'},
    {'name': 'Linen', 'hex': '#FAF0E6'},
    {'name': 'Snow', 'hex': '#FFFAFA'},
    {'name': 'Alice Blue', 'hex': '#F0F8FF'},
    {'name': 'Ghost White', 'hex': '#F8F8FF'},
    {'name': 'Honeydew', 'hex': '#F0FFF0'},
  ];

  List<Map<String, String>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _colors;
    return _colors
        .where(
          (c) =>
              (c['name'] ?? '').toLowerCase().contains(q) ||
              (c['hex'] ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  Color _parseHex(String hex) {
    final normalized = hex.replaceAll('#', '');
    return Color(int.parse('FF$normalized', radix: 16));
  }

  Future<void> _copyHex(String hex) async {
    await Clipboard.setData(ClipboardData(text: hex));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('colors.magazine.copied'.tr(args: [hex]))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = _filtered;
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final isTablet =
        MediaQuery.of(context).size.width >= 600 &&
        MediaQuery.of(context).size.width < 1024;

    final crossAxisCount = isDesktop ? 5 : (isTablet ? 4 : 2);

    return Scaffold(
      appBar: AppBar(title: Text('colors.magazine.title'.tr())),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(isDesktop ? 24 : 16),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'colors.magazine.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'colors.magazine.no_results'.tr(),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.all(isDesktop ? 24 : 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: isDesktop ? 20 : 16,
                        mainAxisSpacing: isDesktop ? 20 : 16,
                        childAspectRatio: isDesktop ? 1.1 : 1.0,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final hex = item['hex'] ?? '#000000';
                        final name = item['name'] ?? '';
                        final color = _parseHex(hex);

                        final onColor =
                            ThemeData.estimateBrightnessForColor(color) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black;

                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _copyHex(hex),
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outline.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: colorScheme.outline.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          hex,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: onColor,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.5,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'colors.magazine.tap_to_copy'.tr(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colorScheme.onSurface
                                                    .withValues(alpha: 0.6),
                                              ),
                                        ),
                                      ),
                                      Icon(
                                        LucideIcons.copy,
                                        size: 16,
                                        color: colorScheme.primary,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
