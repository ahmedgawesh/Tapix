import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../utils/platform_utils.dart';

/// RevenueCat configuration constants
class RevenueCatConfig {
  RevenueCatConfig._();

  /// API key for RevenueCat
  static const String apiKey = 'goog_bmcvleZZMqUhtEkYvqaknUJRzvB';

  /// Entitlement identifier for Tapix Pro
  static const String entitlementId = 'pro';

  /// Product identifiers (must match Google Play Console)
  static const String weeklyProductId = 'com.tapix.pos';
  static const String monthlyProductId = 'com.tapix.pos.monthly';
  static const String yearlyProductId = 'com.tapix.pos.yearly';
  static const String lifetimeProductId = 'com.tapix.pos.lifetime';

  /// All product identifiers
  static const List<String> allProductIds = [
    weeklyProductId,
    monthlyProductId,
    yearlyProductId,
    lifetimeProductId,
  ];

  /// Whether RevenueCat is supported on the current platform
  static bool get isSupported => PlatformUtils.isAndroid || PlatformUtils.isIOS;
}

/// Subscription type derived from the product identifier
enum SubscriptionType {
  weekly,
  monthly,
  yearly,
  lifetime,
  none;

  static SubscriptionType fromProductId(String? productId) {
    if (productId == null) return none;
    // Check longer (more specific) IDs first to avoid false matches
    if (productId == RevenueCatConfig.lifetimeProductId) return lifetime;
    if (productId == RevenueCatConfig.yearlyProductId) return yearly;
    if (productId == RevenueCatConfig.monthlyProductId) return monthly;
    if (productId == RevenueCatConfig.weeklyProductId) return weekly;
    return none;
  }

  /// Maximum allowed offline days before forced revalidation
  int get maxOfflineDays {
    switch (this) {
      case weekly:
        return 3;
      case monthly:
        return 7;
      case yearly:
        return 14;
      case lifetime:
        return 30;
      case none:
        return 0;
    }
  }
}

/// Subscription status model
class SubscriptionStatus {
  final bool isActive;
  final bool isPro;
  final String? activeProductId;
  final SubscriptionType subscriptionType;
  final DateTime? expirationDate;
  final bool willRenew;
  final String? userId;

  const SubscriptionStatus({
    this.isActive = false,
    this.isPro = false,
    this.activeProductId,
    this.subscriptionType = SubscriptionType.none,
    this.expirationDate,
    this.willRenew = false,
    this.userId,
  });

  factory SubscriptionStatus.fromCustomerInfo(CustomerInfo? info) {
    if (info == null) {
      return const SubscriptionStatus();
    }

    final entitlement = info.entitlements.all[RevenueCatConfig.entitlementId];
    final isActive = entitlement?.isActive ?? false;
    final productId = entitlement?.productIdentifier;

    return SubscriptionStatus(
      isActive: isActive,
      isPro: isActive,
      activeProductId: productId,
      subscriptionType: SubscriptionType.fromProductId(productId),
      expirationDate: entitlement?.expirationDate != null
          ? DateTime.tryParse(entitlement!.expirationDate!)
          : null,
      willRenew: entitlement?.willRenew ?? false,
      userId: info.originalAppUserId,
    );
  }

  bool get isLifetime => subscriptionType == SubscriptionType.lifetime;

  SubscriptionStatus copyWith({
    bool? isActive,
    bool? isPro,
    String? activeProductId,
    SubscriptionType? subscriptionType,
    DateTime? expirationDate,
    bool? willRenew,
    String? userId,
  }) {
    return SubscriptionStatus(
      isActive: isActive ?? this.isActive,
      isPro: isPro ?? this.isPro,
      activeProductId: activeProductId ?? this.activeProductId,
      subscriptionType: subscriptionType ?? this.subscriptionType,
      expirationDate: expirationDate ?? this.expirationDate,
      willRenew: willRenew ?? this.willRenew,
      userId: userId ?? this.userId,
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

/// RevenueCat service for managing subscriptions.
/// Only initializes on Android and iOS.
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

  /// Initialize RevenueCat SDK.
  /// Returns immediately on unsupported platforms (web, desktop).
  Future<void> initialize({String? appUserId}) async {
    if (!RevenueCatConfig.isSupported) {
      debugPrint('RevenueCat: Skipped – unsupported platform');
      return;
    }

    if (_isInitialized) {
      debugPrint('RevenueCat: Already initialized');
      return;
    }

    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }

      final configuration = PurchasesConfiguration(RevenueCatConfig.apiKey);

      if (appUserId != null && appUserId.isNotEmpty) {
        configuration.appUserID = appUserId;
      }

      await Purchases.configure(configuration);

      Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);

      _isInitialized = true;
      debugPrint('RevenueCat: Initialized successfully');

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

  /// Check subscription and return status. Returns inactive on unsupported platforms.
  Future<SubscriptionStatus> checkSubscription() async {
    if (!RevenueCatConfig.isSupported || !_isInitialized) {
      return const SubscriptionStatus();
    }

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return SubscriptionStatus.fromCustomerInfo(customerInfo);
    } catch (e) {
      debugPrint('RevenueCat: Failed to check subscription: $e');
      return const SubscriptionStatus();
    }
  }

  /// Refresh and broadcast subscription status
  Future<SubscriptionStatus> refreshSubscriptionStatus() async {
    final status = await checkSubscription();
    _subscriptionStatusController.add(status);
    return status;
  }

  /// Get available offerings
  Future<Offerings?> getOfferings() async {
    _ensureInitialized();

    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('RevenueCat: Failed to get offerings: $e');
      return null;
    }
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

  /// Restore purchases
  Future<PurchaseResult> restorePurchases() async {
    _ensureInitialized();

    try {
      final customerInfo = await Purchases.restorePurchases();
      debugPrint('RevenueCat: Restore successful');
      return PurchaseResult.success(customerInfo);
    } catch (e) {
      debugPrint('RevenueCat: Restore error: $e');
      return PurchaseResult.error(e.toString());
    }
  }

  /// Open Google Play subscription management
  Future<void> openSubscriptionManagement() async {
    // On Android, deep-link to Google Play subscriptions page
    // Users can cancel/change subscriptions there
    debugPrint('RevenueCat: Opening subscription management');
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

  /// Set user attributes for analytics
  Future<void> setUserAttributes({
    String? email,
    String? displayName,
    String? phoneNumber,
  }) async {
    _ensureInitialized();

    try {
      if (email != null) await Purchases.setEmail(email);
      if (displayName != null) await Purchases.setDisplayName(displayName);
      if (phoneNumber != null) await Purchases.setPhoneNumber(phoneNumber);
    } catch (e) {
      debugPrint('RevenueCat: Set attributes error: $e');
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
