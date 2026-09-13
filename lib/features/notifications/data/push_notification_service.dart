import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/features/notifications/data/push_device_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  PushNotificationService({PushDeviceRepository? repository})
    : _repository = repository ?? PushDeviceRepository();

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final PushDeviceRepository _repository;
  final StreamController<Uri> _eventLinks = StreamController<Uri>.broadcast();
  final StreamController<ForegroundPushNotification> _foregroundNotifications =
      StreamController<ForegroundPushNotification>.broadcast();
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenSubscription;
  Future<bool>? _initialization;
  String? _registeredToken;
  bool _allowTokenRegistration = false;

  Stream<Uri> get eventLinks => _eventLinks.stream;
  Stream<ForegroundPushNotification> get foregroundNotifications =>
      _foregroundNotifications.stream;

  Future<Uri?> initialize() async {
    final enabled = await (_initialization ??= _initializeOnce());
    if (!enabled) return null;
    return _eventUri(await FirebaseMessaging.instance.getInitialMessage());
  }

  Future<void> registerCurrentDevice() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    if (!await (_initialization ??= _initializeOnce())) return;

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: Platform.isIOS,
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      await messaging.setAutoInitEnabled(false);
      return;
    }
    if (Supabase.instance.client.auth.currentSession == null) {
      await messaging.setAutoInitEnabled(false);
      return;
    }
    _allowTokenRegistration = true;

    if (Platform.isIOS && !await _waitForApnsToken(messaging)) return;

    final token = await messaging.getToken();
    if (token == null || token.trim().isEmpty) return;
    if (Supabase.instance.client.auth.currentSession == null) return;
    await _register(token);
  }

  Future<void> unregisterCurrentDevice() async {
    _allowTokenRegistration = false;
    if (!await (_initialization ??= _initializeOnce())) return;
    var token = _registeredToken;
    if (token == null || token.isEmpty) {
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {
        // Local token deletion below still protects a signed-out device.
      }
    }
    try {
      if (token != null && token.isNotEmpty) {
        await _repository.unregister(token);
      }
    } finally {
      _registeredToken = null;
      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.setAutoInitEnabled(false);
        await messaging.deleteToken();
      } catch (_) {
        // The server-side token will be disabled if FCM later rejects it.
      }
    }
  }

  Future<bool> _initializeOnce() async {
    if (!AppConfig.remotePushEnabled) return false;
    final options = _firebaseOptions;
    if (options == null) return false;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(false);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      final uri = _eventUri(message);
      if (uri != null) _eventLinks.add(uri);
    });
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      if (!Platform.isAndroid) return;
      final notification = message.notification;
      _foregroundNotifications.add(
        ForegroundPushNotification(
          title: notification?.title ?? 'Event update',
          body: notification?.body ?? '',
          eventLink: _eventUri(message),
        ),
      );
    });
    _tokenSubscription = messaging.onTokenRefresh.listen((token) {
      if (_allowTokenRegistration &&
          Supabase.instance.client.auth.currentSession != null) {
        unawaited(_register(token).catchError((_) {}));
      }
    });
    return true;
  }

  Future<bool> _waitForApnsToken(FirebaseMessaging messaging) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      if (await messaging.getAPNSToken() != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<void> _register(String token) async {
    final platform = Platform.isIOS ? 'ios' : 'android';
    await _repository.register(
      token: token,
      platform: platform,
      locale: PlatformDispatcher.instance.locale.toLanguageTag(),
    );
    _registeredToken = token;
  }

  FirebaseOptions? get _firebaseOptions {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    final apiKey = Platform.isIOS
        ? AppConfig.firebaseIosApiKey
        : AppConfig.firebaseAndroidApiKey;
    final appId = Platform.isIOS
        ? AppConfig.firebaseIosAppId
        : AppConfig.firebaseAndroidAppId;
    if ([
      apiKey,
      appId,
      AppConfig.firebaseMessagingSenderId,
      AppConfig.firebaseProjectId,
    ].any((value) => value.trim().isEmpty)) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: AppConfig.firebaseMessagingSenderId,
      projectId: AppConfig.firebaseProjectId,
      iosBundleId: Platform.isIOS ? AppConfig.firebaseIosBundleId : null,
    );
  }

  Uri? _eventUri(RemoteMessage? message) {
    final eventId = message?.data['event_id'];
    if (eventId == null || !_uuidPattern.hasMatch(eventId)) return null;
    return Uri(scheme: 'gather2gether', host: 'event', path: '/$eventId');
  }

  Future<void> dispose() async {
    await _openedSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _eventLinks.close();
    await _foregroundNotifications.close();
  }
}

class ForegroundPushNotification {
  const ForegroundPushNotification({
    required this.title,
    required this.body,
    required this.eventLink,
  });

  final String title;
  final String body;
  final Uri? eventLink;
}
