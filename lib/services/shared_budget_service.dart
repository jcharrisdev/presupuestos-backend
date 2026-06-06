import 'dart:convert';
import 'api_client.dart';
import 'auth_service.dart';

class SharedBudgetService {
  static Future<List<dynamic>> getAll(String uid) async {
    final res = await ApiClient.get('/shared-budgets?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body) as List;
    return [];
  }

  static Future<Map<String, dynamic>?> getDetail(int id, String uid) async {
    final res = await ApiClient.get('/shared-budgets/$id?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body);
    return null;
  }

  static Future<Map<String, dynamic>?> create(Map<String, dynamic> body) async {
    // Z2 — adjuntar nombre real del usuario para mostrarlo a los demás miembros
    body['display_name'] ??= AuthService.currentUser?.displayName;
    final res = await ApiClient.post('/shared-budgets', body);
    if (res.statusCode == 201) return json.decode(res.body);
    return null;
  }

  static Future<bool> invite(
    int budgetId,
    String emailInvitado,
    String uid, {
    String rolInvitado = 'participante',
  }) async {
    final res = await ApiClient.post('/shared-budgets/$budgetId/invitations', {
      'email_invitado': emailInvitado,
      'firebase_uid': uid,
      'rol_invitado': rolInvitado,
    });
    return res.statusCode == 201;
  }

  static Future<List<dynamic>> getInvitations(String uid) async {
    final res = await ApiClient.get('/shared-budget-invitations?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body) as List;
    return [];
  }

  static Future<bool> acceptInvitation(String token, String uid, {double? ingresoDeclarado}) async {
    final body = <String, dynamic>{'firebase_uid': uid};
    if (ingresoDeclarado != null) body['ingreso_declarado'] = ingresoDeclarado;
    final nombre = AuthService.currentUser?.displayName;
    if (nombre != null && nombre.isNotEmpty) body['display_name'] = nombre;
    final res = await ApiClient.post('/shared-budget-invitations/$token/accept', body);
    return res.statusCode == 200;
  }

  static Future<bool> rejectInvitation(String token, String uid) async {
    final res = await ApiClient.post('/shared-budget-invitations/$token/reject', {'firebase_uid': uid});
    return res.statusCode == 200;
  }

  static Future<bool> createExpense(int budgetId, Map<String, dynamic> body) async {
    final res = await ApiClient.post('/shared-budgets/$budgetId/expenses', body);
    return res.statusCode == 201;
  }

  static Future<List<dynamic>> getExpenses(int budgetId, String uid) async {
    final res = await ApiClient.get('/shared-budgets/$budgetId/expenses?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body) as List;
    return [];
  }

  static Future<bool> createSettlement(int budgetId, Map<String, dynamic> body) async {
    final res = await ApiClient.post('/shared-budgets/$budgetId/settlements', body);
    return res.statusCode == 201;
  }

  static Future<List<dynamic>> getSettlements(int budgetId, String uid) async {
    final res = await ApiClient.get('/shared-budgets/$budgetId/settlements?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body) as List;
    return [];
  }

  static Future<bool> deleteExpense(int expenseId, String uid) async {
    final res = await ApiClient.delete('/shared-expenses/$expenseId?firebase_uid=$uid');
    return res.statusCode == 200;
  }

  static Future<bool> confirmarMiParte(int expenseId, String uid) async {
    final res = await ApiClient.post('/shared-expenses/$expenseId/confirm-payment', {'firebase_uid': uid});
    return res.statusCode == 200;
  }

  static Future<bool> requestDelete(int budgetId, String uid) async {
    final res = await ApiClient.post('/shared-budgets/$budgetId/request-delete', {'firebase_uid': uid});
    return res.statusCode == 200;
  }

  static Future<bool> updateMember(
    int budgetId,
    String memberUid,
    String ownerUid, {
    double? porcentaje,
    double? ingresoDeclarado,
    double? contribucionMensual,
  }) async {
    final body = <String, dynamic>{'firebase_uid': ownerUid};
    if (porcentaje != null) body['porcentaje'] = porcentaje;
    if (ingresoDeclarado != null) body['ingreso_declarado'] = ingresoDeclarado;
    if (contribucionMensual != null) body['contribucion_mensual'] = contribucionMensual;
    final res = await ApiClient.patch('/shared-budgets/$budgetId/members/$memberUid', body);
    return res.statusCode == 200;
  }

  // Sprint 8: cambiar rol de un miembro
  static Future<bool> changeRole(
    int budgetId,
    String memberUid,
    String myUid,
    String nuevoRol,
  ) async {
    final res = await ApiClient.patch(
      '/shared-budgets/$budgetId/members/$memberUid/rol',
      {'firebase_uid': myUid, 'rol': nuevoRol},
    );
    return res.statusCode == 200;
  }

  // Retorna el nivel numérico del rol para comparaciones de UI
  static int rolLevel(String? rol) {
    const levels = {'creador': 4, 'admin': 3, 'participante': 2, 'lectura': 1, 'owner': 4, 'member': 2};
    return levels[rol] ?? 0;
  }

  static bool canEdit(String? rol) => rolLevel(rol) >= rolLevel('admin');
  static bool canAddExpense(String? rol) => rolLevel(rol) >= rolLevel('participante');
  static bool isCreador(String? rol) => rol == 'creador' || rol == 'owner';
}
