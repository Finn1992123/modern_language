import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_navigation.dart';

const _announcementChannel = AndroidNotificationChannel(
  'announcements',
  'Ανακοινώσεις',
  description: 'Νέες ανακοινώσεις του Modern Language',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<AuthState>? _authSubscription;
  static String? _registeredToken;
  static String? _pendingNotificationId;
  static String? _preferenceAuthUserId;
  static bool _isAvailable = false;
  static bool _canReceiveNotifications = false;
  static bool _announcementNotificationsEnabled = false;

  static Future<void> initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    try {
      await Firebase.initializeApp();
      _isAvailable = true;
    } catch (_) {
      // Firebase configuration is added separately for each native app.
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('notification_small'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null && id.isNotEmpty) {
          _openOrQueueAnnouncement(id);
        }
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_announcementChannel);

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessage);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleRemoteMessage(initialMessage);
    }

    _tokenSubscription = messaging.onTokenRefresh.listen((token) {
      if (_announcementNotificationsEnabled) {
        unawaited(_replaceToken(token));
      }
    });

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.event == AuthChangeEvent.signedIn) {
        unawaited(_activateForCurrentUser());
      } else if (state.event == AuthChangeEvent.tokenRefreshed) {
        unawaited(syncCurrentDevice());
      } else if (state.event == AuthChangeEvent.signedOut) {
        _preferenceAuthUserId = null;
        _announcementNotificationsEnabled = false;
        _canReceiveNotifications = false;
      }
    });

    await _activateForCurrentUser();
  }

  static Future<bool> getAnnouncementNotificationsEnabled() async {
    final authUserId = Supabase.instance.client.auth.currentUser?.id;
    if (authUserId == null) return false;

    if (_preferenceAuthUserId == authUserId) {
      return _announcementNotificationsEnabled;
    }

    final preferences = await SharedPreferences.getInstance();
    _preferenceAuthUserId = authUserId;
    _announcementNotificationsEnabled =
        preferences.getBool(_preferenceKey(authUserId)) ?? true;
    return _announcementNotificationsEnabled;
  }

  static Future<bool> setAnnouncementNotificationsEnabled(bool enabled) async {
    final authUserId = Supabase.instance.client.auth.currentUser?.id;
    if (authUserId == null) return false;

    final preferences = await SharedPreferences.getInstance();

    if (!enabled) {
      final didUnregister = await unregisterCurrentDevice();
      if (!didUnregister) return false;

      await preferences.setBool(_preferenceKey(authUserId), false);
      _preferenceAuthUserId = authUserId;
      _announcementNotificationsEnabled = false;
      _canReceiveNotifications = false;
      return true;
    }

    if (!_isAvailable || !await _requestSystemPermission()) {
      await preferences.setBool(_preferenceKey(authUserId), false);
      _preferenceAuthUserId = authUserId;
      _announcementNotificationsEnabled = false;
      return false;
    }

    await preferences.setBool(_preferenceKey(authUserId), true);
    _preferenceAuthUserId = authUserId;
    _announcementNotificationsEnabled = true;
    await syncCurrentDevice();
    return true;
  }

  static Future<bool> syncCurrentDevice() async {
    if (!_isAvailable ||
        !_canReceiveNotifications ||
        !_announcementNotificationsEnabled ||
        Supabase.instance.client.auth.currentUser == null) {
      return false;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return false;
      await _replaceToken(token);
      return true;
    } catch (_) {
      // Registration will be retried on the next login or token refresh.
      return false;
    }
  }

  static Future<bool> unregisterCurrentDevice() async {
    if (!_isAvailable) return true;

    try {
      final token =
          _registeredToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return true;
      await Supabase.instance.client.rpc(
        'unregister_push_notification_device',
        params: {'input_token': token},
      );
      _registeredToken = null;
      return true;
    } catch (_) {
      // Signing out must still be possible if the token cannot be removed.
      return false;
    }
  }

  static Future<void> _replaceToken(String token) async {
    if (!_announcementNotificationsEnabled ||
        Supabase.instance.client.auth.currentUser == null) {
      return;
    }

    final oldToken = _registeredToken;
    if (oldToken != null && oldToken != token) {
      try {
        await Supabase.instance.client.rpc(
          'unregister_push_notification_device',
          params: {'input_token': oldToken},
        );
      } catch (_) {
        // The new token is still registered below.
      }
    }

    await Supabase.instance.client.rpc(
      'register_push_notification_device',
      params: {
        'input_token': token,
        'input_platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      },
    );
    _registeredToken = token;
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (!_announcementNotificationsEnabled) return;

    final title = message.notification?.title ?? 'Νέα ανακοίνωση';
    final body = message.notification?.body ?? '';
    final notificationId = message.data['notification_id']?.toString() ?? '';

    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'announcements',
          'Ανακοινώσεις',
          channelDescription: 'Νέες ανακοινώσεις του Modern Language',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'notification_small',
          largeIcon: DrawableResourceAndroidBitmap('notification_large'),
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: notificationId,
    );
  }

  static void _handleRemoteMessage(RemoteMessage message) {
    if (!_announcementNotificationsEnabled) return;

    final id = message.data['notification_id']?.toString();
    if (id != null && id.isNotEmpty) {
      _openOrQueueAnnouncement(id);
    }
  }

  static void _openOrQueueAnnouncement(String notificationId) {
    if (!openAnnouncementFromNotification(notificationId)) {
      _pendingNotificationId = notificationId;
    }
  }

  static void openPendingNotification() {
    final id = _pendingNotificationId;
    if (id == null) return;
    if (openAnnouncementFromNotification(id)) {
      _pendingNotificationId = null;
    }
  }

  static Future<void> _activateForCurrentUser() async {
    if (!_isAvailable ||
        Supabase.instance.client.auth.currentUser == null ||
        !await getAnnouncementNotificationsEnabled()) {
      return;
    }

    if (!await _requestSystemPermission()) {
      final authUserId = Supabase.instance.client.auth.currentUser?.id;
      if (authUserId != null) {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setBool(_preferenceKey(authUserId), false);
      }
      _announcementNotificationsEnabled = false;
      return;
    }

    await syncCurrentDevice();
  }

  static Future<bool> _requestSystemPermission() async {
    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _canReceiveNotifications =
        permission.authorizationStatus == AuthorizationStatus.authorized ||
        permission.authorizationStatus == AuthorizationStatus.provisional;
    return _canReceiveNotifications;
  }

  static String _preferenceKey(String authUserId) =>
      'announcement_notifications_enabled_$authUserId';

  static Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
  }
}
