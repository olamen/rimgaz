import 'dart:isolate';
import 'dart:ui';

import 'package:background_locator_2/background_locator.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:background_locator_2/settings/android_settings.dart';
import 'package:background_locator_2/settings/ios_settings.dart';
import 'package:background_locator_2/settings/locator_settings.dart';
import 'package:flutter/material.dart';

/// Service utilitaire pour préparer le tracking GPS en arrière-plan
/// avec background_locator_2. Rien n'est encore branché dans l'UI,
/// mais tout est prêt à être utilisé.
class BackgroundTrackingService {
  static const String _isolateName = 'RimGazLocatorIsolate';
  static final ReceivePort _port = ReceivePort();

  static bool _initialized = false;

  /// À appeler une seule fois au démarrage de l'app (ex: dans main()
  /// ou au premier écran après login chauffeur) avant start().
  static Future<void> initialize() async {
    if (_initialized) return;

    final alreadyRegistered =
        IsolateNameServer.lookupPortByName(_isolateName) != null;
    if (!alreadyRegistered) {
      IsolateNameServer.registerPortWithName(
        _port.sendPort,
        _isolateName,
      );
    }

    _port.listen((dynamic data) {
      // Optionnel: mettre à jour l'UI avec la dernière position reçue
      // par exemple via un Stream/Provider.
      // debugPrint('Background location: $data');
    });

    await BackgroundLocator.initialize();
    _initialized = true;
  }

  /// Démarre le tracking en arrière-plan.
  /// À appeler quand le chauffeur commence sa tournée.
  static Future<void> start() async {
    await initialize();

    await BackgroundLocator.registerLocationUpdate(
      LocationCallbackHandler.callback,
      initCallback: LocationCallbackHandler.initCallback,
      disposeCallback: LocationCallbackHandler.disposeCallback,
      autoStop: false,
      iosSettings: const IOSSettings(
        accuracy: LocationAccuracy.NAVIGATION,
        distanceFilter: 0,
      ),
      androidSettings: AndroidSettings(
        accuracy: LocationAccuracy.NAVIGATION,
        interval: 20, // secondes entre deux updates approx.
        distanceFilter: 0,
        androidNotificationSettings: const AndroidNotificationSettings(
          notificationChannelName: 'RimGaz tracking',
          notificationTitle: 'Suivi RimGaz',
          notificationMsg: 'Suivi de la tournée en arrière-plan',
          notificationBigMsg:
              'RimGaz suit votre bus en arrière-plan pour la tournée.',
          notificationIcon: '',
          notificationIconColor: Colors.blue,
          notificationTapCallback: LocationCallbackHandler.notificationCallback,
        ),
      ),
    );
  }

  /// Arrête le tracking en arrière-plan.
  /// À appeler quand le chauffeur termine sa journée.
  static Future<void> stop() async {
    IsolateNameServer.removePortNameMapping(_isolateName);
    await BackgroundLocator.unRegisterLocationUpdate();
    _initialized = false;
  }
}

/// Classe qui contient les callbacks appelés en arrière-plan.
class LocationCallbackHandler {
  @pragma('vm:entry-point')
  static void callback(LocationDto locationDto) async {
    final SendPort? send = IsolateNameServer.lookupPortByName(
      BackgroundTrackingService._isolateName,
    );
    send?.send(locationDto);

    // TODO: ici, envoyer la position vers le backend /api/bus-positions/
    // en utilisant http.post et, si nécessaire, le token JWT.
    // Exemple (pseudo-code) :
    // final uri = Uri.parse('http://127.0.0.1:8000/api/bus-positions/');
    // await http.post(uri, ...);
  }

  @pragma('vm:entry-point')
  static void initCallback(dynamic initData) {
    // Optional: initialisation du callback background (chargement config, etc.)
  }

  @pragma('vm:entry-point')
  static void disposeCallback() {
    // Optional: nettoyage quand le tracking s'arrête
  }

  @pragma('vm:entry-point')
  static void notificationCallback() {
    // Optional: réagir au clic sur la notification Android
  }
}
