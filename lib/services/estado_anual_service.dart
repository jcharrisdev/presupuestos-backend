import 'dart:convert';
import 'api_client.dart';

class EstadoAnualService {
  static Future<Map<String, dynamic>> getEstadoAnual(String uid, int anio) async {
    final res = await ApiClient.get('/user/estado-anual/$anio?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
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
    final res = await ApiClient.get('/user/meses/$anio/$mes?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
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
}
