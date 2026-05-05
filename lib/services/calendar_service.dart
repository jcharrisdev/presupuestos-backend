import 'dart:convert';
import 'api_client.dart';

class CalendarService {
  static Future<List<Map<String, dynamic>>> getEventos(String uid, int mes, int anio) async {
    final res = await ApiClient.get('/calendario/eventos?firebase_uid=$uid&mes=$mes&anio=$anio');
    if (res.statusCode == 200) {
      return (json.decode(res.body) as List).cast<Map<String, dynamic>>();
    }
    throw Exception('Error al obtener eventos (${res.statusCode})');
  }

  static Future<void> updateEstado(int id, String estado, String uid) async {
    final res = await ApiClient.put('/calendario/eventos/$id/estado', {'estado': estado, 'firebase_uid': uid});
    if (res.statusCode != 200) throw Exception('Error al actualizar estado (${res.statusCode})');
  }

  static Future<void> deleteEvento(int id, String uid, bool soloEste) async {
    final res = await ApiClient.delete('/calendario/eventos/$id?firebase_uid=$uid&solo_este=${soloEste ? 1 : 0}');
    if (res.statusCode != 200) throw Exception('Error al eliminar evento (${res.statusCode})');
  }
}
