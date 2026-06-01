import 'dart:convert';
import 'api_client.dart';

class GustitosService {
  static Future<List<dynamic>> listar(String uid) async {
    final res = await ApiClient.get('/gustitos?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body) as List;
    throw Exception('Error al cargar Gustitos');
  }

  static Future<List<dynamic>> listarDelMes(String uid, int anio, int mes) async {
    final res = await ApiClient.get('/gustitos?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception('Error al cargar Gustitos');
    final todos = json.decode(res.body) as List;
    return todos.where((g) {
      final fecha = DateTime.tryParse(g['spent_at'] ?? '');
      return fecha != null && fecha.year == anio && fecha.month == mes;
    }).toList();
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
