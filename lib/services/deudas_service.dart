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
    return jsonDecode(res.body) as Map<String, dynamic>;
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
}
