import 'dart:convert';
import 'api_client.dart';

class IncomeService {
  static Future<Map<String, dynamic>?> getIncome(
      int presupuestoId, String uid) async {
    try {
      final res = await ApiClient.get(
          '/presupuestos/$presupuestoId/income?firebase_uid=$uid');
      if (res.statusCode == 204) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> upsertIncome(
      int presupuestoId, Map<String, dynamic> body) async {
    final res =
        await ApiClient.post('/presupuestos/$presupuestoId/income', body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>?> getCapacidad(
      int presupuestoId, String uid) async {
    try {
      final res = await ApiClient.get(
          '/presupuestos/$presupuestoId/capacidad?firebase_uid=$uid');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getFondoSeguridad(
      int presupuestoId, String uid) async {
    try {
      final res = await ApiClient.get(
          '/presupuestos/$presupuestoId/fondo-seguridad?firebase_uid=$uid');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getPatronesGustitos(
      int presupuestoId, String uid) async {
    try {
      final res = await ApiClient.get(
          '/presupuestos/$presupuestoId/gustitos/patrones?firebase_uid=$uid');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getResumenCierre(
      int presupuestoId, int periodoId, String uid) async {
    try {
      final res = await ApiClient.get(
          '/presupuestos/$presupuestoId/periodo/$periodoId/resumen-cierre?firebase_uid=$uid');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> cerrarPeriodo(
      int presupuestoId, int periodoId, String uid) async {
    final res = await ApiClient.post(
        '/presupuestos/$presupuestoId/periodo/$periodoId/cerrar',
        {'firebase_uid': uid});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // #4 — Distribución por clasificación financiera
  static Future<Map<String, dynamic>?> getDistribucionClasificacion(
      int presupuestoId, String uid) async {
    try {
      final res = await ApiClient.get(
          '/presupuestos/$presupuestoId/distribucion-clasificacion?firebase_uid=$uid');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // #6 — Alertas inteligentes preventivas
  static Future<Map<String, dynamic>?> getAlertas(
      int presupuestoId, String uid) async {
    try {
      final res = await ApiClient.get(
          '/presupuestos/$presupuestoId/alertas?firebase_uid=$uid');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // #7 — Recomendación por porcentajes (regla 50/30/20)
  static Future<Map<String, dynamic>?> getRecomendacionPorcentajes(
      int presupuestoId, String uid) async {
    try {
      final res = await ApiClient.get(
          '/presupuestos/$presupuestoId/recomendacion-porcentajes?firebase_uid=$uid');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
