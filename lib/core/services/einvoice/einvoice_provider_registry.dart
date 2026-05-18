import 'einvoice_provider.dart';
import 'einvoice_status.dart';
import 'providers/null_einvoice_provider.dart';

/// Registry selecting the right provider for the company's configured
/// jurisdiction. When no jurisdiction is configured (or set to `NONE`),
/// the [NullEInvoiceProvider] is returned so dispatch is a no-op.
///
/// Register per-country providers once at app boot, keyed by the value
/// of [EInvoiceProvider.jurisdiction].
class EInvoiceProviderRegistry {
  final Map<EInvoiceJurisdiction, EInvoiceProvider> _providers;
  final EInvoiceProvider _fallback;

  EInvoiceProviderRegistry({
    List<EInvoiceProvider> providers = const [],
    EInvoiceProvider? fallback,
  })  : _providers = {for (final p in providers) p.jurisdiction: p},
        _fallback = fallback ?? const NullEInvoiceProvider();

  /// Look up the provider for [jurisdiction]; returns the fallback
  /// (null provider by default) when nothing is registered.
  EInvoiceProvider resolve(EInvoiceJurisdiction jurisdiction) {
    return _providers[jurisdiction] ?? _fallback;
  }

  /// Returns `true` if a non-null provider is registered for [j].
  bool hasProvider(EInvoiceJurisdiction j) =>
      j != EInvoiceJurisdiction.none && _providers.containsKey(j);
}
