import 'dart:convert';
import 'api_client.dart';

class SavingsService {
  static Future<List<Map<String, dynamic>>> getAhorros(String uid) async {
    final res = await ApiClient.get('/ahorros?firebase_uid=$uid');
    if (res.statusCode == 200) {
      return (json.decode(res.body) as List).cast<Map<String, dynamic>>();
    }
    throw Exception('Error al obtener ahorros (${res.statusCode})');
  }

  static Future<void> deleteAhorro(int id, String uid) async {
    final res = await ApiClient.delete('/ahorros/$id?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception('Error al eliminar ahorro (${res.statusCode})');
  }
}
