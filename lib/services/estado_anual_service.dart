import 'dart:convert';
import 'api_client.dart';
import 'cache_service.dart';

class EstadoAnualService {
  static Future<Map<String, dynamic>> getEstadoAnual(String uid, int anio) async {
    final cacheKey = '${uid}_estado_anual_$anio';
    try {
      final res = await ApiClient.get('/user/estado-anual/$anio?firebase_uid=$uid');
      if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await CacheService.set(cacheKey, data);
      return data;
    } catch (e) {
      final cached = CacheService.get(cacheKey, maxAge: const Duration(hours: 48));
      if (cached != null) return Map<String, dynamic>.from(cached as Map);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> generarEstadoAnual(String uid, {int? anio}) async {
    final res = await ApiClient.post('/user/estado-anual/generar', {
      'firebase_uid': uid,
      if (anio != null) 'anio': anio,
    });
    if (res.statusCode != 201) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getMes(String uid, int anio, int mes) async {
    final cacheKey = '${uid}_mes_${anio}_$mes';
    try {
      final res = await ApiClient.get('/user/meses/$anio/$mes?firebase_uid=$uid');
      if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await CacheService.set(cacheKey, data);
      return data;
    } catch (e) {
      final cached = CacheService.get(cacheKey, maxAge: const Duration(hours: 24));
      if (cached != null) return Map<String, dynamic>.from(cached as Map);
      rethrow;
    }
  }

  // FIN-02: desglose por categoría (presupuestado vs real) + comparación con
  // meses anteriores + insights automáticos.
  static Future<Map<String, dynamic>> getAnalisisVariaciones(String uid, int anio, int mes) async {
    final cacheKey = '${uid}_analisis_variaciones_${anio}_$mes';
    try {
      final res = await ApiClient.get('/user/meses/$anio/$mes/analisis-variaciones?firebase_uid=$uid');
      if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await CacheService.set(cacheKey, data);
      return data;
    } catch (e) {
      final cached = CacheService.get(cacheKey, maxAge: const Duration(hours: 24));
      if (cached != null) return Map<String, dynamic>.from(cached as Map);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> cerrarMes(String uid, int anio, int mes) async {
    final res = await ApiClient.post('/user/cerrar-mes-financiero/$anio/$mes', {'firebase_uid': uid});
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getProyeccionSiguienteAnio(String uid, int anio) async {
    final res = await ApiClient.get('/user/proyeccion-siguiente-anio/$anio?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> cerrarAnio(String uid, int anio) async {
    final res = await ApiClient.post('/user/cerrar-anio/$anio', {'firebase_uid': uid});
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getAlertas(String uid, {int? anio, int? mes}) async {
    var path = '/user/alertas?firebase_uid=$uid&leidas=0';
    if (anio != null) path += '&anio=$anio';
    if (mes != null) path += '&mes=$mes';
    final res = await ApiClient.get(path);
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<void> marcarAlertaLeida(String uid, int alertaId) async {
    await ApiClient.patch('/user/alertas/$alertaId/leer', {'firebase_uid': uid});
  }

  static Future<Map<String, dynamic>> getResumenAlertas(String uid, int anio) async {
    final res = await ApiClient.get('/user/alertas/resumen?firebase_uid=$uid&anio=$anio');
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> registrarIngresoReal(
      String uid, int anio, int mes, double ingresoReal) async {
    final res = await ApiClient.patch('/user/meses/$anio/$mes/ingreso', {
      'firebase_uid': uid,
      'ingreso_real': ingresoReal,
    });
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }
}
