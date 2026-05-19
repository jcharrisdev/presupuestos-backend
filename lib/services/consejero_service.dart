import 'dart:convert';
import 'api_client.dart';

class ConsejeroService {
  static Future<Map<String, dynamic>> get(
    String uid, {
    required int anio,
    required int mes,
  }) async {
    final r = await ApiClient.get('/user/consejero?firebase_uid=$uid&anio=$anio&mes=$mes');
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
