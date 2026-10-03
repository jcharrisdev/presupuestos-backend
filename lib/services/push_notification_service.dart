/// Notificaciones push reales (Firebase Cloud Messaging), solo plataforma Web.
///
/// Distinto de [NotificationService] (notificaciones locales del calendario,
/// sin servidor): este servicio pide permiso del navegador, obtiene el token
/// FCM y lo registra en el backend para que `lib/push_notifications.js` pueda
/// empujar avisos aunque la pestaña esté cerrada.
///
/// El permiso se pide solo a usuarios que ya pasaron el onboarding (ver
/// `home_shell.dart`) — pedirlo en la primera pantalla, antes de que el
/// usuario vea valor, generaría más rechazos que aceptaciones.
library;

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart';
import 'api_client.dart';

class PushNotificationService {
  // Generado en Firebase Console → Project Settings → Cloud Messaging →
  // Web Push certificates. No es secreto (se usa desde el navegador).
  static const _vapidKey =
      'BFmtI_U1zMlGew-7djvB0vMkgYSIqI5GWxvW1INEJrtjcEM64cTpQy70zLibxBM2VMUt4ub4ebRS-FEQqUR77Gc';

  static bool _firebaseReady = false;

  /// Inicializa Firebase. Seguro de llamar siempre — si falla (ej. el
  /// proyecto no está configurado), el resto de la app sigue funcionando
  /// sin push, no debe tumbar el arranque.
  static Future<void> inicializar() async {
    if (_firebaseReady) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _firebaseReady = true;
    } catch (e) {
      debugPrint('[push_notification_service] Firebase no se pudo inicializar: $e');
    }
  }

  /// Pide permiso de notificaciones y registra el token con el backend.
  /// No hace nada si Firebase no inicializó o si el usuario ya rechazó el
  /// permiso antes (el navegador recuerda esa decisión, no se re-pregunta).
  static Future<void> solicitarPermisoYRegistrar(String firebaseUid) async {
    if (!_firebaseReady) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus != AuthorizationStatus.authorized) return;

      final token = await messaging.getToken(vapidKey: _vapidKey);
      if (token != null) await _registrar(firebaseUid, token);

      messaging.onTokenRefresh.listen((nuevoToken) => _registrar(firebaseUid, nuevoToken));
    } catch (e) {
      debugPrint('[push_notification_service] no se pudo registrar el token: $e');
    }
  }

  static Future<void> _registrar(String firebaseUid, String token) async {
    try {
      await ApiClient.post('/notifications/register-token', {
        'firebase_uid': firebaseUid,
        'token': token,
        'plataforma': 'web',
      });
    } catch (e) {
      debugPrint('[push_notification_service] error registrando token: $e');
    }
  }
}
