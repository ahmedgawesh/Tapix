import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../firebase_options.dart';

import '../utils/platform_utils.dart';
import 'logging_service.dart';

/// Firebase background entry point.
///
/// This intentionally contains no subscription/license logic. Push messaging is
/// an independent communication channel owned by TapBix Notifications.
@pragma('vm:entry-point')
Future<void> tapbixFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const String _registrationUrl =
      'https://tapixsolutions.com/wp-json/tapbix-push/v1/register';
  static const String _installIdKey = 'tapbix_push_install_id_v1';
  static const String _channelId = 'tapbix_general';
  static const String _channelName = 'TapBix Notifications';
  static const String _languageTopicKey = 'tapbix_push_language_topic_v1';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: const {
        'Content-Type': 'application/json',
        'X-TapBix-Client': 'push-registration-v1',
      },
    ),
  );

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;

  bool get _isSupported =>
      !kIsWeb && (PlatformUtils.isAndroid || PlatformUtils.isIOS);

  Future<void> initialize() async {
    if (_initialized || !_isSupported) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(
      tapbixFirebaseMessagingBackgroundHandler,
    );

    await _initializeLocalNotifications();

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!allowed) {
        LoggingService.info('Push notifications permission not granted');
        return;
      }

      await _subscribeToDefaultTopics();
      await _syncLanguageTopic();
      await _registerCurrentToken();

      _tokenSubscription = _messaging.onTokenRefresh.listen(
        (token) => unawaited(_registerToken(token)),
        onError: (Object error, StackTrace stackTrace) {
          LoggingService.error(
            'Push token refresh failed',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );

      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        (message) => unawaited(_showForegroundNotification(message)),
      );

      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
      );

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleOpenedMessage(initialMessage);
      }
    } catch (error, stackTrace) {
      // Push must never prevent TapBix from starting.
      LoggingService.error(
        'Push notifications initialization failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        LoggingService.info(
          'Local notification opened: ${response.payload ?? 'no-payload'}',
        );
      },
    );

    if (PlatformUtils.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'General messages and updates from TapBix.',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> _subscribeToDefaultTopics() async {
    await _messaging.subscribeToTopic('tapbix_all');
    if (PlatformUtils.isAndroid) {
      await _messaging.subscribeToTopic('tapbix_android');
    } else if (PlatformUtils.isIOS) {
      await _messaging.subscribeToTopic('tapbix_ios');
    }
  }

  /// Re-syncs the selected TapBix language and refreshes this device's
  /// registration metadata. Safe to call after the user changes language.
  Future<void> refreshRegistration() async {
    if (!_initialized || !_isSupported) return;
    try {
      await _syncLanguageTopic();
      await _registerCurrentToken();
    } catch (error, stackTrace) {
      LoggingService.error(
        'Push registration refresh failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _syncLanguageTopic() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = _selectedTapBixLanguage(prefs);
    final nextTopic = 'tapbix_lang_$locale';
    final previousTopic = prefs.getString(_languageTopicKey);

    if (previousTopic != null &&
        previousTopic.isNotEmpty &&
        previousTopic != nextTopic) {
      await _messaging.unsubscribeFromTopic(previousTopic);
    }

    await _messaging.subscribeToTopic(nextTopic);
    await prefs.setString(_languageTopicKey, nextTopic);
  }

  String _selectedTapBixLanguage(SharedPreferences prefs) {
    final code = (prefs.getString('locale_code') ?? 'en').toLowerCase();
    return const {'ar', 'en', 'fr'}.contains(code) ? code : 'en';
  }

  Future<void> _registerCurrentToken() async {
    if (PlatformUtils.isIOS) {
      // On Apple platforms the APNs token can arrive slightly later than FCM.
      for (var attempt = 0; attempt < 5; attempt++) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    final token = await _messaging.getToken();
    if (token == null || token.trim().isEmpty) {
      LoggingService.info('Push registration token is not available yet');
      return;
    }
    await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var installId = prefs.getString(_installIdKey);
      if (installId == null || installId.isEmpty) {
        installId = const Uuid().v4();
        await prefs.setString(_installIdKey, installId);
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final platform = PlatformUtils.isAndroid ? 'android' : 'ios';
      final locale = _selectedTapBixLanguage(prefs);
      final deviceName = await _readDeviceName();

      await _dio.post<void>(
        _registrationUrl,
        data: <String, dynamic>{
          'token': token,
          'install_id': installId,
          'platform': platform,
          'locale': locale,
          'app_version': '${packageInfo.version}+${packageInfo.buildNumber}',
          'device_name': deviceName,
          'notifications_enabled': true,
        },
      );

      LoggingService.info('Push device registered successfully');
    } catch (error, stackTrace) {
      // Registration failure is non-fatal. FCM topic subscriptions still work,
      // and registration is retried on the next app start/token refresh.
      LoggingService.error(
        'Push device registration failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<String> _readDeviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (PlatformUtils.isAndroid) {
        final android = await info.androidInfo;
        final label = '${android.manufacturer} ${android.model}'.trim();
        return label.isEmpty ? 'Android device' : label;
      }
      if (PlatformUtils.isIOS) {
        final ios = await info.iosInfo;
        final label = '${ios.name} ${ios.model}'.trim();
        return label.isEmpty ? 'iOS device' : label;
      }
    } catch (_) {
      // Device label is optional metadata only.
    }
    return 'Unknown device';
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'General messages and updates from TapBix.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title: notification.title ?? 'TapBix',
      body: notification.body ?? '',
      notificationDetails: details,
      payload: jsonEncode(message.data),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    // Phase 1 behavior: tapping a notification opens TapBix.
    // Deep links can be added later without touching licensing.
    LoggingService.info(
      'Push notification opened: ${jsonEncode(message.data)}',
    );
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}
