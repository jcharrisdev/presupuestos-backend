import 'dart:convert';
import 'api_client.dart';

class GustitosService {
  static Future<List<dynamic>> listarPorPresupuesto(int budgetId, String uid) async {
    final res = await ApiClient.get('/presupuestos/$budgetId/gustitos?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body) as List;
    throw Exception('Error al cargar Gustitos');
  }

  static Future<Map<String, dynamic>> resumen(int budgetId, String uid) async {
    final res = await ApiClient.get('/presupuestos/$budgetId/gustitos/summary?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body) as Map<String, dynamic>;
    return {'total': 0.0, 'count': 0, 'promedio': 0.0, 'ultimos': []};
  }

  static Future<Map<String, dynamic>> crear(Map<String, dynamic> body) async {
    final res = await ApiClient.post('/gustitos', body);
    if (res.statusCode == 201) return json.decode(res.body) as Map<String, dynamic>;
    throw Exception('Error al crear Gustito');
  }

  static Future<void> eliminar(int id, String uid) async {
    await ApiClient.delete('/gustitos/$id?firebase_uid=$uid');
  }

  static Future<Map<String, dynamic>> editar(int id, Map<String, dynamic> body) async {
    final res = await ApiClient.patch('/gustitos/$id', body);
    if (res.statusCode == 200) return json.decode(res.body) as Map<String, dynamic>;
    throw Exception('Error al editar Gustito');
  }
}
