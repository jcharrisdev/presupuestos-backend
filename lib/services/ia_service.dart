import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class IaService {
  /// Se incrementa cada vez que el usuario confirma una acción IA.
  /// Cualquier widget puede escucharlo con addListener para auto-recargarse.
  static final actionRefreshNotifier = ValueNotifier<int>(0);
  static void notifyActionCompleted() => actionRefreshNotifier.value++;

  static Future<Map<String, dynamic>> diagnostico(
    String uid, {
    int? presupuestoId,
  }) async {
    final r = await ApiClient.post('/ai/diagnostico', {
      'firebase_uid': uid,
      if (presupuestoId != null) 'presupuesto_id': presupuestoId,
    });
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> chat(
    String uid,
    String mensaje, {
    int? presupuestoId,
    List<Map<String, dynamic>> historial = const [],
  }) async {
    final r = await ApiClient.post('/ai/chat', {
      'firebase_uid': uid,
      'mensaje': mensaje,
      if (presupuestoId != null) 'presupuesto_id': presupuestoId,
      'historial': historial,
    });
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> categorizar(
    String uid,
    String descripcion,
    double monto,
  ) async {
    final r = await ApiClient.post('/ai/categorizar', {
      'firebase_uid': uid,
      'descripcion': descripcion,
      'monto': monto,
    });
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> reporte(
    String uid, {
    int? presupuestoId,
    int? anio,
    int? mes,
  }) async {
    final r = await ApiClient.post('/ai/reporte', {
      'firebase_uid': uid,
      if (presupuestoId != null) 'presupuesto_id': presupuestoId,
      if (anio != null) 'anio': anio,
      if (mes  != null) 'mes': mes,
    });
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<String> nudge(String uid, {int? anio, int? mes}) async {
    final r = await ApiClient.post('/ai/nudge', {
      'firebase_uid': uid,
      if (anio != null) 'anio': anio,
      if (mes  != null) 'mes': mes,
    });
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return data['nudge'] as String? ?? '';
  }

  static Future<Map<String, dynamic>> explicarAlerta(
    String uid,
    int alertaId,
  ) async {
    final r = await ApiClient.post('/ai/explicar-alerta', {
      'firebase_uid': uid,
      'alerta_id': alertaId,
    });
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> simularDecision(
    String uid,
    String pregunta,
  ) async {
    final r = await ApiClient.post('/ai/simular-decision', {
      'firebase_uid': uid,
      'pregunta': pregunta,
    });
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> confirmarAccion(String uid, int accionId) async {
    final r = await ApiClient.post('/acciones/$accionId/confirmar', {'firebase_uid': uid});
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body)['error'] ?? 'Error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<void> cancelarAccion(String uid, int accionId) async {
    final r = await ApiClient.post('/acciones/$accionId/cancelar', {'firebase_uid': uid});
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
  }

  static Future<List<Map<String, dynamic>>> accionesPendientes(String uid) async {
    final r = await ApiClient.get('/acciones/pendientes?firebase_uid=$uid');
    if (r.statusCode != 200) return [];
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['acciones'] as List? ?? []).cast<Map<String, dynamic>>();
  }
}
