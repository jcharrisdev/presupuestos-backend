import 'dart:convert';
import 'api_client.dart';

class DeudasService {
  static Future<Map<String, dynamic>> getAll(String uid, {bool incluirSaldadas = false}) async {
    final param = incluirSaldadas ? '&incluir_saldadas=1' : '';
    final res = await ApiClient.get('/deudas?firebase_uid=$uid$param');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> crear(Map<String, dynamic> body) async {
    final res = await ApiClient.post('/deudas', body);
    if (res.statusCode == 201) return jsonDecode(res.body) as Map<String, dynamic>;
    final err = jsonDecode(res.body)['error'] ?? 'Error ${res.statusCode}';
    throw Exception(err);
  }

  static Future<Map<String, dynamic>> editar(int id, Map<String, dynamic> body) async {
    final res = await ApiClient.put('/deudas/$id', body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> registrarAbono(
      int id, String uid, double monto, {String? fechaProximoPago}) async {
    final body = <String, dynamic>{'firebase_uid': uid, 'monto_abono': monto};
    if (fechaProximoPago != null) body['fecha_proximo_pago'] = fechaProximoPago;
    final res = await ApiClient.patch('/deudas/$id/abono', body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> archivar(int id, String uid) async {
    await ApiClient.delete('/deudas/$id?firebase_uid=$uid');
  }

  static Future<Map<String, dynamic>> getProyeccion(String uid) async {
    final res = await ApiClient.get('/deudas/proyeccion?firebase_uid=$uid');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getSimulador(
      String uid, double extraMensual, String estrategia) async {
    final res = await ApiClient.get(
        '/deudas/simulador?firebase_uid=$uid&extra_mensual=$extraMensual&estrategia=$estrategia');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getPlan(
      String uid, String estrategia, double extraMensual) async {
    final res = await ApiClient.get(
        '/deudas/plan?firebase_uid=$uid&estrategia=$estrategia&extra_mensual=$extraMensual');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
