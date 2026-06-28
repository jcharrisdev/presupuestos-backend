import 'dart:convert';
import 'api_client.dart';

class IngresoExtraService {
  static Future<Map<String, dynamic>> getByMes(String uid, int anio, int mes) async {
    try {
      final res = await ApiClient.get('/user/ingresos-extra?firebase_uid=$uid&anio=$anio&mes=$mes');
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
      return {'ingresos': [], 'total': 0.0, 'buckets': []};
    } catch (_) {
      return {'ingresos': [], 'total': 0.0, 'buckets': []};
    }
  }

  static Future<Map<String, dynamic>?> crear(String uid, {
    required double monto,
    required String fuenteNombre,
    required String fecha,
    String? descripcion,
  }) async {
    final res = await ApiClient.post('/user/ingresos-extra', {
      'firebase_uid': uid,
      'monto': monto,
      'fuente_nombre': fuenteNombre,
      'fecha': fecha,
      if (descripcion != null) 'descripcion': descripcion,
    });
    if (res.statusCode == 201) return jsonDecode(res.body) as Map<String, dynamic>;
    final err = jsonDecode(res.body)['error'] ?? 'Error al guardar';
    throw Exception(err);
  }

  static Future<void> eliminar(String uid, int id) async {
    final res = await ApiClient.delete('/user/ingresos-extra/$id', body: {'firebase_uid': uid});
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body)['error'] ?? 'Error al eliminar';
      throw Exception(err);
    }
  }
}
