import 'dart:convert';
import 'api_client.dart';

/// Servicio para el perfil financiero global del usuario.
/// El ingreso y los compromisos fijos existen una sola vez — no por presupuesto.
class UserProfileService {
  // ── Income global ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getIncome(String uid) async {
    try {
      final res = await ApiClient.get('/user/income?firebase_uid=$uid');
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        return data['tiene_income'] == true ? data : null;
      }
      return null;
    } catch (_) { return null; }
  }

  static Future<Map<String, dynamic>?> upsertIncome(String uid, Map<String, dynamic> body) async {
    try {
      final res = await ApiClient.post('/user/income', {'firebase_uid': uid, ...body});
      if (res.statusCode == 200) return json.decode(res.body) as Map<String, dynamic>;
      return null;
    } catch (_) { return null; }
  }

  // ── Gastos fijos globales ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getGastosFijos(String uid) async {
    try {
      final res = await ApiClient.get('/user/gastos-fijos?firebase_uid=$uid');
      if (res.statusCode == 200) return json.decode(res.body) as Map<String, dynamic>;
      return {'gastos': [], 'total_mensual': 0};
    } catch (_) { return {'gastos': [], 'total_mensual': 0}; }
  }

  static Future<Map<String, dynamic>> crearGastoFijo(String uid, Map<String, dynamic> body) async {
    final res = await ApiClient.post('/user/gastos-fijos', {'firebase_uid': uid, ...body});
    if (res.statusCode == 201) return json.decode(res.body) as Map<String, dynamic>;
    final errorMsg = json.decode(res.body)['error'] ?? 'Error ${res.statusCode}';
    throw Exception(errorMsg);
  }

  static Future<bool> actualizarGastoFijo(int id, String uid, Map<String, dynamic> body) async {
    final res = await ApiClient.put('/user/gastos-fijos/$id', {'firebase_uid': uid, ...body});
    if (res.statusCode == 200) return true;
    final errorMsg = json.decode(res.body)['error'] ?? 'Error ${res.statusCode}';
    throw Exception(errorMsg);
  }

  static Future<bool> eliminarGastoFijo(int id, String uid) async {
    try {
      final res = await ApiClient.delete('/user/gastos-fijos/$id?firebase_uid=$uid');
      return res.statusCode == 200;
    } catch (_) { return false; }
  }

  // ── Perfil completo ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getPerfilCompleto(String uid) async {
    try {
      final res = await ApiClient.get('/user/perfil-financiero?firebase_uid=$uid');
      if (res.statusCode == 200) return json.decode(res.body) as Map<String, dynamic>;
      return null;
    } catch (_) { return null; }
  }

  // ── Ahorros activos del usuario (cuota mensual para el perfil) ──────────
  static Future<Map<String, dynamic>> getAhorrosActivos(String uid) async {
    try {
      final res = await ApiClient.get('/user/ahorros-activos?firebase_uid=$uid');
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
      return {'ahorros': [], 'total_cuota_mensual': 0};
    } catch (_) { return {'ahorros': [], 'total_cuota_mensual': 0}; }
  }

  // ── Sync deudas del perfil (crea deuda_id faltantes) ─────────────────────
  static Future<void> syncDeudas(String uid) async {
    try {
      await ApiClient.post('/user/sync-deudas', {'firebase_uid': uid});
    } catch (_) {}
  }

  // ── Eliminar ingreso (para reconfigurar) ──────────────────────────────────

  static Future<bool> deleteIncome(String uid) async {
    try {
      final res = await ApiClient.delete('/user/income', body: {'firebase_uid': uid});
      return res.statusCode == 200;
    } catch (_) { return false; }
  }

  // ── Borrar todos los datos ────────────────────────────────────────────────

  static Future<bool> borrarTodosLosDatos(String uid) async {
    try {
      // DELETE con body (firebase_uid como confirmación)
      final res = await ApiClient.delete('/user/data', body: {'firebase_uid': uid});
      return res.statusCode == 200;
    } catch (_) { return false; }
  }

  // ── Helpers de cálculo (local) ────────────────────────────────────────────

  static double ingresoNeto(Map<String, dynamic>? income) =>
      double.tryParse(income?['ingreso_neto_mensual']?.toString() ?? '0') ?? 0;

  static double ingresoPorPeriodo(Map<String, dynamic>? income, String tipoPeriodo) {
    final neto = ingresoNeto(income);
    return tipoPeriodo == 'quincenal' ? neto / 2 : neto;
  }
}
