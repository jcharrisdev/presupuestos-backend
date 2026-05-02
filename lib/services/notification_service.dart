import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId   = 'salarying_pagos';
  static const _channelName = 'Recordatorios de pagos';

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId, _channelName,
          description: 'Alertas de pagos próximos',
          importance: Importance.high,
        ));
    _initialized = true;
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> mostrarRecordatorio({
    required int id,
    required String titulo,
    required double monto,
    required String fechaEvento,
    required int diasRestantes,
  }) async {
    await init();
    final body = diasRestantes == 0
        ? 'Vence HOY · \$${monto.toStringAsFixed(2)}'
        : 'Vence en $diasRestantes ${diasRestantes == 1 ? "día" : "días"} · \$${monto.toStringAsFixed(2)}';

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

  static Future<void> mostrarResumenDiario(List<Map<String, dynamic>> proximos) async {
    if (proximos.isEmpty) return;
    await init();
    final body = proximos.length == 1
        ? '${proximos[0]['titulo']} · \$${proximos[0]['monto_esperado']}'
        : '${proximos.length} pagos próximos en los siguientes 3 días';

    await _plugin.show(
      0, 'Recordatorio de pagos', body,
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

  static Future<void> cancelar(int id) => _plugin.cancel(id);
  static Future<void> cancelarTodos() => _plugin.cancelAll();
}
