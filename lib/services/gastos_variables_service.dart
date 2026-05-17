import 'dart:convert';
import 'api_client.dart';

class GastosVariablesService {
  static Future<Map<String, dynamic>> getAll(String uid) async {
    final res = await ApiClient.get('/user/gastos-variables-base?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> crear({
    required String uid,
    required String nombre,
    required String categoria,
    required double montoEstimado,
    String frecuencia = 'mensual',
    String? notas,
    int? subcategoriaId,
    List<int>? aplicaMeses,
  }) async {
    final res = await ApiClient.post('/user/gastos-variables-base', {
      'firebase_uid': uid,
      'nombre': nombre,
      'categoria': categoria,
      'monto_estimado': montoEstimado,
      'frecuencia': frecuencia,
      if (notas != null) 'notas': notas,
      if (subcategoriaId != null) 'subcategoria_id': subcategoriaId,
      if (aplicaMeses != null) 'aplica_meses': aplicaMeses,
    });
    if (res.statusCode != 201) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> editar(String uid, int id, Map<String, dynamic> data) async {
    final res = await ApiClient.put('/user/gastos-variables-base/$id', {'firebase_uid': uid, ...data});
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<void> eliminar(String uid, int id) async {
    await ApiClient.delete('/user/gastos-variables-base/$id?firebase_uid=$uid');
  }

  static Future<List<dynamic>> getSubcategorias(String uid, {String? categoria}) async {
    var path = '/user/subcategorias?firebase_uid=$uid';
    if (categoria != null) path += '&categoria=$categoria';
    final res = await ApiClient.get(path);
    if (res.statusCode != 200) return [];
    return jsonDecode(res.body) as List;
  }

  static Future<Map<String, dynamic>> crearSubcategoria(String uid, String categoria, String nombre) async {
    final res = await ApiClient.post('/user/subcategorias', {
      'firebase_uid': uid, 'categoria': categoria, 'nombre': nombre,
    });
    if (res.statusCode != 201) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }
}
