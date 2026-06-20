import 'dart:convert';
import 'api_client.dart';

class IaService {
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
}
