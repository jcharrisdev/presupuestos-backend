import 'dart:convert';
import 'api_client.dart';

class SobresService {
  static Future<List<dynamic>> getCategorias(int presupuestoId, String uid) async {
    final res = await ApiClient.get(
        '/presupuestos/$presupuestoId/categorias?firebase_uid=$uid');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['categorias'] as List? ?? [];
  }

  static Future<Map<String, dynamic>> crearCategoria(
      int presupuestoId, Map<String, dynamic> body) async {
    final res = await ApiClient.post('/presupuestos/$presupuestoId/categorias', body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> editarCategoria(
      int presupuestoId, int catId, Map<String, dynamic> body) async {
    final res = await ApiClient.put(
        '/presupuestos/$presupuestoId/categorias/$catId', body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> eliminarCategoria(
      int presupuestoId, int catId, String uid) async {
    await ApiClient.delete(
        '/presupuestos/$presupuestoId/categorias/$catId?firebase_uid=$uid');
  }

  static Future<Map<String, dynamic>> getResumenSobres(
      int presupuestoId, String uid, {int? periodoId}) async {
    final extra = periodoId != null ? '&periodo_id=$periodoId' : '';
    final res = await ApiClient.get(
        '/presupuestos/$presupuestoId/resumen-sobres?firebase_uid=$uid$extra');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> registrarGasto(
      int presupuestoId, Map<String, dynamic> body) async {
    final res = await ApiClient.post(
        '/presupuestos/$presupuestoId/gastos-rapidos', body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getGastos(
      int presupuestoId, String uid, {int? periodoId}) async {
    final extra = periodoId != null ? '&periodo_id=$periodoId' : '';
    final res = await ApiClient.get(
        '/presupuestos/$presupuestoId/gastos-rapidos?firebase_uid=$uid$extra');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> eliminarGasto(
      int presupuestoId, int gastoId, String uid) async {
    await ApiClient.delete(
        '/presupuestos/$presupuestoId/gastos-rapidos/$gastoId?firebase_uid=$uid');
  }
}
