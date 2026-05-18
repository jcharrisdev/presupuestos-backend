import 'dart:convert';
import 'api_client.dart';

class EventosService {
  static Future<Map<String, dynamic>> getEventos(String uid, int anio) async {
    final res = await ApiClient.get('/user/eventos?firebase_uid=$uid&anio=$anio');
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getEvento(String uid, int id) async {
    final res = await ApiClient.get('/user/eventos/$id?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> crearEvento(String uid, Map<String, dynamic> body) async {
    final res = await ApiClient.post('/user/eventos', {'firebase_uid': uid, ...body});
    if (res.statusCode != 201) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<void> editarEvento(String uid, int id, Map<String, dynamic> body) async {
    final res = await ApiClient.put('/user/eventos/$id', {'firebase_uid': uid, ...body});
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
  }

  static Future<void> cancelarEvento(String uid, int id) async {
    final res = await ApiClient.delete('/user/eventos/$id?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
  }

  static Future<Map<String, dynamic>> agregarGasto(
      String uid, int eventoId, Map<String, dynamic> body) async {
    final res = await ApiClient.post('/user/eventos/$eventoId/gastos', {'firebase_uid': uid, ...body});
    if (res.statusCode != 201) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<void> eliminarGasto(String uid, int eventoId, int gastoId) async {
    final res = await ApiClient.delete(
        '/user/eventos/$eventoId/gastos/$gastoId?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
  }
}
