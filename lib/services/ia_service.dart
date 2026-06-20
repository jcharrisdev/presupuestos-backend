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
    String uid,
    int presupuestoId,
  ) async {
    final r = await ApiClient.post('/ai/reporte', {
      'firebase_uid': uid,
      'presupuesto_id': presupuestoId,
    });
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
