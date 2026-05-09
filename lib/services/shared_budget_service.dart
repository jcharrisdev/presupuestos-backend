import 'dart:convert';
import 'api_client.dart';

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
    final res = await ApiClient.post('/shared-budgets', body);
    if (res.statusCode == 201) return json.decode(res.body);
    return null;
  }

  static Future<bool> invite(int budgetId, String emailInvitado, String uid) async {
    final res = await ApiClient.post('/shared-budgets/$budgetId/invitations', {
      'email_invitado': emailInvitado,
      'firebase_uid': uid,
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
}
