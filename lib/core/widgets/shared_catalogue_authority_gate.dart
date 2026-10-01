import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Prevents an independent branch from editing coordinator-owned product and
/// supplier master data. The branch may keep posting local documents offline;
/// only the shared identity/catalogue definition is centralized.
class SharedCatalogueAuthorityGate extends StatefulWidget {
  const SharedCatalogueAuthorityGate({
    super.key,
    required this.title,
    required this.authorityCheck,
    required this.child,
  });

  final String title;
  final Future<bool> Function() authorityCheck;
  final Widget child;

  @override
  State<SharedCatalogueAuthorityGate> createState() =>
      _SharedCatalogueAuthorityGateState();
}

class _SharedCatalogueAuthorityGateState
    extends State<SharedCatalogueAuthorityGate> {
  late Future<bool> _authority;

  @override
  void initState() {
    super.initState();
    _authority = widget.authorityCheck();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _authority,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.data == true) return widget.child;
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hub_outlined,
                          size: 48,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'business_locations.catalogue_authority.title'.tr(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'business_locations.catalogue_authority.body'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back),
                          label: Text(
                            'business_locations.catalogue_authority.back'.tr(),
                          ),
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
    },
  );
}
