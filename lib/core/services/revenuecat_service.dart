import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// RevenueCat configuration constants
class RevenueCatConfig {
  RevenueCatConfig._();

  /// API key for RevenueCat
  static const String apiKey = 'test_zPRbbXCRZAfmpKYzLZdDOGuxoQA';

  /// Entitlement identifier for Tapix Pro
  static const String entitlementId = 'Tapix Pro';

  /// Product identifiers
  static const String weeklyProductId = 'weekly';
  static const String monthlyProductId = 'monthly';
  static const String yearlyProductId = 'yearly';
  static const String lifetimeProductId = 'lifetime';

  /// All product identifiers
  static const List<String> allProductIds = [
    weeklyProductId,
    monthlyProductId,
    yearlyProductId,
    lifetimeProductId,
  ];
}

/// Subscription status model
class SubscriptionStatus {
  final bool isActive;
  final bool isPro;
  final String? activeProductId;
  final DateTime? expirationDate;
  final bool willRenew;
  final CustomerInfo? customerInfo;

  const SubscriptionStatus({
    this.isActive = false,
    this.isPro = false,
    this.activeProductId,
    this.expirationDate,
    this.willRenew = false,
    this.customerInfo,
  });

  factory SubscriptionStatus.fromCustomerInfo(CustomerInfo? info) {
    if (info == null) {
      return const SubscriptionStatus();
    }

    final entitlement = info.entitlements.all[RevenueCatConfig.entitlementId];
    final isActive = entitlement?.isActive ?? false;

    return SubscriptionStatus(
      isActive: isActive,
      isPro: isActive,
      activeProductId: entitlement?.productIdentifier,
      expirationDate: entitlement?.expirationDate != null
          ? DateTime.tryParse(entitlement!.expirationDate!)
          : null,
      willRenew: entitlement?.willRenew ?? false,
      customerInfo: info,
    );
  }

  bool get isLifetime =>
      activeProductId == RevenueCatConfig.lifetimeProductId ||
      (isActive && expirationDate == null);

  SubscriptionStatus copyWith({
    bool? isActive,
    bool? isPro,
    String? activeProductId,
    DateTime? expirationDate,
    bool? willRenew,
    CustomerInfo? customerInfo,
  }) {
    return SubscriptionStatus(
      isActive: isActive ?? this.isActive,
      isPro: isPro ?? this.isPro,
      activeProductId: activeProductId ?? this.activeProductId,
      expirationDate: expirationDate ?? this.expirationDate,
      willRenew: willRenew ?? this.willRenew,
      customerInfo: customerInfo ?? this.customerInfo,
    );
  }
}

/// Purchase result model
class PurchaseResult {
  final bool success;
  final bool userCancelled;
  final String? errorMessage;
  final CustomerInfo? customerInfo;

  const PurchaseResult({
    this.success = false,
    this.userCancelled = false,
    this.errorMessage,
    this.customerInfo,
  });

  factory PurchaseResult.success(CustomerInfo info) {
    return PurchaseResult(
      success: true,
      customerInfo: info,
    );
  }

  factory PurchaseResult.cancelled() {
    return const PurchaseResult(userCancelled: true);
  }

  factory PurchaseResult.error(String message) {
    return PurchaseResult(errorMessage: message);
  }
}

/// RevenueCat service for managing subscriptions
class RevenueCatService {
  RevenueCatService._();

  static final RevenueCatService _instance = RevenueCatService._();
  static RevenueCatService get instance => _instance;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  final _subscriptionStatusController =
      StreamController<SubscriptionStatus>.broadcast();

  /// Stream of subscription status updates
  Stream<SubscriptionStatus> get subscriptionStatusStream =>
      _subscriptionStatusController.stream;

  /// Initialize RevenueCat SDK
  /// Should be called once at app startup
  Future<void> initialize({String? appUserId}) async {
    if (_isInitialized) {
      debugPrint('RevenueCat: Already initialized');
      return;
    }

    try {
      // Enable debug logs in debug mode
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }

      // Configure RevenueCat
      final configuration = PurchasesConfiguration(RevenueCatConfig.apiKey);

      if (appUserId != null && appUserId.isNotEmpty) {
        configuration.appUserID = appUserId;
      }

      await Purchases.configure(configuration);

      // Listen for customer info updates
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);

      _isInitialized = true;
      debugPrint('RevenueCat: Initialized successfully');

      // Fetch initial customer info
      await refreshSubscriptionStatus();
    } catch (e, st) {
      debugPrint('RevenueCat: Initialization failed: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  void _onCustomerInfoUpdated(CustomerInfo info) {
    debugPrint('RevenueCat: Customer info updated');
    final status = SubscriptionStatus.fromCustomerInfo(info);
    _subscriptionStatusController.add(status);
  }

  /// Get current subscription status
  Future<SubscriptionStatus> getSubscriptionStatus() async {
    _ensureInitialized();

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return SubscriptionStatus.fromCustomerInfo(customerInfo);
    } catch (e) {
      debugPrint('RevenueCat: Failed to get subscription status: $e');
      return const SubscriptionStatus();
    }
  }

  /// Refresh and broadcast subscription status
  Future<SubscriptionStatus> refreshSubscriptionStatus() async {
    final status = await getSubscriptionStatus();
    _subscriptionStatusController.add(status);
    return status;
  }

  /// Check if user has active Tapix Pro entitlement
  Future<bool> hasProEntitlement() async {
    final status = await getSubscriptionStatus();
    return status.isPro;
  }

  /// Get available offerings
  Future<Offerings?> getOfferings() async {
    _ensureInitialized();

    try {
      final offerings = await Purchases.getOfferings();
      return offerings;
    } catch (e) {
      debugPrint('RevenueCat: Failed to get offerings: $e');
      return null;
    }
  }

  /// Get current offering
  Future<Offering?> getCurrentOffering() async {
    final offerings = await getOfferings();
    return offerings?.current;
  }

  /// Purchase a package
  Future<PurchaseResult> purchasePackage(Package package) async {
    _ensureInitialized();

    try {
      final purchaseParams = PurchaseParams.package(package);
      final result = await Purchases.purchase(purchaseParams);
      debugPrint('RevenueCat: Purchase successful');
      return PurchaseResult.success(result.customerInfo);
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('RevenueCat: Purchase cancelled by user');
        return PurchaseResult.cancelled();
      }
      debugPrint('RevenueCat: Purchase error: $errorCode');
      return PurchaseResult.error(_getErrorMessage(errorCode));
    } catch (e) {
      debugPrint('RevenueCat: Purchase error: $e');
      return PurchaseResult.error(e.toString());
    }
  }

  /// Purchase a product by ID
  Future<PurchaseResult> purchaseProduct(String productId) async {
    _ensureInitialized();

    try {
      final offerings = await getOfferings();
      final currentOffering = offerings?.current;

      if (currentOffering == null) {
        return PurchaseResult.error('No offerings available');
      }

      // Find the package with the matching product ID
      final package = currentOffering.availablePackages.firstWhere(
        (p) => p.storeProduct.identifier == productId,
        orElse: () => throw Exception('Product not found: $productId'),
      );

      return purchasePackage(package);
    } catch (e) {
      debugPrint('RevenueCat: Purchase product error: $e');
      return PurchaseResult.error(e.toString());
    }
  }

  /// Restore purchases
  Future<PurchaseResult> restorePurchases() async {
    _ensureInitialized();

    try {
      final customerInfo = await Purchases.restorePurchases();
      debugPrint('RevenueCat: Restore successful');
      return PurchaseResult.success(customerInfo);
    } on PurchasesErrorCode catch (e) {
      debugPrint('RevenueCat: Restore error: $e');
      return PurchaseResult.error(_getErrorMessage(e));
    } catch (e) {
      debugPrint('RevenueCat: Restore error: $e');
      return PurchaseResult.error(e.toString());
    }
  }

  /// Present the RevenueCat paywall
  Future<PaywallResult> presentPaywall({Offering? offering}) async {
    _ensureInitialized();

    try {
      if (offering != null) {
        return await RevenueCatUI.presentPaywall(offering: offering);
      }
      return await RevenueCatUI.presentPaywall();
    } catch (e) {
      debugPrint('RevenueCat: Present paywall error: $e');
      rethrow;
    }
  }

  /// Present paywall only if user doesn't have the entitlement
  Future<PaywallResult> presentPaywallIfNeeded() async {
    _ensureInitialized();

    try {
      return await RevenueCatUI.presentPaywallIfNeeded(
        RevenueCatConfig.entitlementId,
      );
    } catch (e) {
      debugPrint('RevenueCat: Present paywall if needed error: $e');
      rethrow;
    }
  }

  /// Present Customer Center for subscription management
  Future<void> presentCustomerCenter() async {
    _ensureInitialized();

    try {
      await RevenueCatUI.presentCustomerCenter();
    } catch (e) {
      debugPrint('RevenueCat: Present customer center error: $e');
      rethrow;
    }
  }

  /// Log in a user (for user identification)
  Future<CustomerInfo?> logIn(String appUserId) async {
    _ensureInitialized();

    try {
      final result = await Purchases.logIn(appUserId);
      debugPrint('RevenueCat: User logged in: $appUserId');
      return result.customerInfo;
    } catch (e) {
      debugPrint('RevenueCat: Login error: $e');
      return null;
    }
  }

  /// Log out the current user
  Future<CustomerInfo?> logOut() async {
    _ensureInitialized();

    try {
      final customerInfo = await Purchases.logOut();
      debugPrint('RevenueCat: User logged out');
      return customerInfo;
    } catch (e) {
      debugPrint('RevenueCat: Logout error: $e');
      return null;
    }
  }

  /// Get the current app user ID
  Future<String> getAppUserId() async {
    _ensureInitialized();
    return await Purchases.appUserID;
  }

  /// Check if the current user is anonymous
  Future<bool> isAnonymous() async {
    _ensureInitialized();
    return await Purchases.isAnonymous;
  }

  /// Set user attributes for analytics
  Future<void> setUserAttributes({
    String? email,
    String? displayName,
    String? phoneNumber,
  }) async {
    _ensureInitialized();

    try {
      if (email != null) {
        await Purchases.setEmail(email);
      }
      if (displayName != null) {
        await Purchases.setDisplayName(displayName);
      }
      if (phoneNumber != null) {
        await Purchases.setPhoneNumber(phoneNumber);
      }
    } catch (e) {
      debugPrint('RevenueCat: Set attributes error: $e');
    }
  }

  /// Set custom attributes
  Future<void> setCustomAttribute(String key, String value) async {
    _ensureInitialized();

    try {
      await Purchases.setAttributes({key: value});
    } catch (e) {
      debugPrint('RevenueCat: Set custom attribute error: $e');
    }
  }

  /// Sync purchases with RevenueCat (useful after app reinstall)
  Future<void> syncPurchases() async {
    _ensureInitialized();

    try {
      // Only available on iOS
      if (Platform.isIOS) {
        await Purchases.syncPurchases();
        debugPrint('RevenueCat: Purchases synced');
      }
    } catch (e) {
      debugPrint('RevenueCat: Sync purchases error: $e');
    }
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'RevenueCat is not initialized. Call initialize() first.',
      );
    }
  }

  String _getErrorMessage(PurchasesErrorCode code) {
    switch (code) {
      case PurchasesErrorCode.purchaseCancelledError:
        return 'Purchase was cancelled';
      case PurchasesErrorCode.storeProblemError:
        return 'There was a problem with the app store';
      case PurchasesErrorCode.purchaseNotAllowedError:
        return 'Purchase not allowed on this device';
      case PurchasesErrorCode.purchaseInvalidError:
        return 'Invalid purchase';
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return 'Product not available for purchase';
      case PurchasesErrorCode.productAlreadyPurchasedError:
        return 'Product already purchased';
      case PurchasesErrorCode.networkError:
        return 'Network error. Please check your connection';
      case PurchasesErrorCode.receiptAlreadyInUseError:
        return 'Receipt already in use by another user';
      case PurchasesErrorCode.invalidReceiptError:
        return 'Invalid receipt';
      case PurchasesErrorCode.missingReceiptFileError:
        return 'Missing receipt file';
      case PurchasesErrorCode.invalidCredentialsError:
        return 'Invalid credentials';
      case PurchasesErrorCode.unexpectedBackendResponseError:
        return 'Unexpected server response';
      case PurchasesErrorCode.paymentPendingError:
        return 'Payment is pending';
      case PurchasesErrorCode.invalidAppleSubscriptionKeyError:
        return 'Invalid subscription key';
      case PurchasesErrorCode.ineligibleError:
        return 'User is ineligible for this offer';
      case PurchasesErrorCode.insufficientPermissionsError:
        return 'Insufficient permissions';
      case PurchasesErrorCode.operationAlreadyInProgressError:
        return 'Operation already in progress';
      default:
        return 'An error occurred. Please try again';
    }
  }

  /// Dispose resources
  void dispose() {
    _subscriptionStatusController.close();
  }
}
