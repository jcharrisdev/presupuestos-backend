/// Servicio de notificaciones locales para Android.
///
/// Usa el paquete `flutter_local_notifications` para mostrar alertas
/// al usuario sobre pagos próximos. Las notificaciones son LOCALES
/// (no requieren servidor ni Firebase Messaging) y se generan en el
/// momento en que la app carga el calendario.
///
/// Canal de Android: `salarying_pagos` con importancia ALTA,
/// de modo que aparezca con sonido y en la barra de estado.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/money.dart';

/// Gestión centralizada de notificaciones locales.
///
/// Patrón singleton mediante métodos estáticos. No instanciar.
/// Flujo de uso:
///   1. `await NotificationService.init()` — registra el canal (una sola vez).
///   2. `await NotificationService.requestPermission()` — solicita permiso Android 13+.
///   3. `mostrarRecordatorio(...)` — notificación individual por pago.
///   4. `mostrarResumenDiario(...)` — resumen cuando hay varios pagos próximos.
class NotificationService {
  /// Instancia del plugin. Es un singleton interno del paquete.
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Flag para evitar inicializar el plugin más de una vez.
  static bool _initialized = false;

  /// ID del canal de Android. Debe ser único por app.
  static const _channelId   = 'salarying_pagos';

  /// Nombre visible del canal en Ajustes → Notificaciones del dispositivo.
  static const _channelName = 'Recordatorios de pagos';

  /// Inicializa el plugin y crea el canal de Android.
  ///
  /// Es seguro llamarlo múltiples veces — el flag `_initialized`
  /// previene re-registrar el canal. Se llama en `main()` antes
  /// de `runApp()` para que esté listo cuando el usuario abra
  /// el calendario por primera vez.
  static Future<void> init() async {
    if (_initialized) return;

    // Configuración para Android: usa el ícono del launcher de la app
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    // Crear el canal con importancia ALTA para que aparezca con sonido
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId, _channelName,
          description: 'Alertas de pagos próximos',
          importance: Importance.high,
        ));
    _initialized = true;
  }

  /// Solicita permiso de notificaciones en Android 13+ (API 33+).
  ///
  /// En versiones anteriores el permiso es automático y este método
  /// no hace nada. Se llama también en `main()`.
  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Muestra una notificación individual para un pago específico.
  ///
  /// - [id]: identificador único de la notificación (usar el ID del evento de calendario).
  /// - [titulo]: nombre del gasto, ej: "Alquiler".
  /// - [monto]: monto esperado del pago.
  /// - [fechaEvento]: fecha en formato `YYYY-MM-DD` (informativo, no se usa directamente).
  /// - [diasRestantes]: 0 si vence hoy, N si vence en N días.
  ///
  /// El cuerpo del mensaje varía según si vence hoy o en días futuros:
  ///   `"Vence HOY · $50.00"` vs `"Vence en 2 días · $50.00"`.
  static Future<void> mostrarRecordatorio({
    required int id,
    required String titulo,
    required double monto,
    required String fechaEvento,
    required int diasRestantes,
  }) async {
    await init(); // Garantizar inicialización en caso de llamada directa

    final body = diasRestantes == 0
        ? 'Vence HOY · ${Money.fmt(monto)}'
        : 'Vence en $diasRestantes ${diasRestantes == 1 ? "día" : "días"} · ${Money.fmt(monto)}';

    await _plugin.show(
      id, 'Pago próximo: $titulo', body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Muestra un resumen único cuando hay múltiples pagos próximos.
  ///
  /// Se llama desde [CalendarioScreen] cada vez que se carga el mes,
  /// filtrando eventos pendientes en los próximos 3 días.
  ///
  /// - Si solo hay 1 pago: muestra su nombre y monto.
  /// - Si hay varios: muestra "N pagos próximos en los siguientes 3 días".
  ///
  /// Usa ID fijo `0` para que una nueva carga reemplace la notificación anterior.
  static Future<void> mostrarResumenDiario(List<Map<String, dynamic>> proximos) async {
    if (proximos.isEmpty) return;
    await init();

    final body = proximos.length == 1
        ? '${proximos[0]['titulo']} · B/. ${proximos[0]['monto_esperado']}'
        : '${proximos.length} pagos próximos en los siguientes 3 días';

    await _plugin.show(
      0, // ID 0 → siempre reemplaza la misma notificación de resumen
      'Recordatorio de pagos', body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Cancela una notificación específica por su [id].
  static Future<void> cancelar(int id) => _plugin.cancel(id);

  /// Cancela TODAS las notificaciones activas de la app.
  static Future<void> cancelarTodos() => _plugin.cancelAll();
}
