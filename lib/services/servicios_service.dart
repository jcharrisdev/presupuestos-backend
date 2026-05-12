import 'dart:convert';
import 'api_client.dart';

class ServiciosService {
  static Future<List<dynamic>> getJobs(String firebaseUid) async {
    final res = await ApiClient.get('/jobs?firebase_uid=$firebaseUid');
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error al cargar trabajos: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> createJob(Map<String, dynamic> data) async {
    final res = await ApiClient.post('/jobs', data);
    if (res.statusCode == 201) return json.decode(res.body);
    throw Exception('Error al crear trabajo: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> getJob(int id, String firebaseUid) async {
    final res = await ApiClient.get('/jobs/$id?firebase_uid=$firebaseUid');
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error al cargar trabajo: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> updateJob(int id, Map<String, dynamic> data) async {
    final res = await ApiClient.put('/jobs/$id', data);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error al actualizar trabajo: ${res.statusCode}');
  }

  static Future<void> deleteJob(int id, String firebaseUid) async {
    final res = await ApiClient.delete('/jobs/$id?firebase_uid=$firebaseUid');
    if (res.statusCode != 200) throw Exception('Error al eliminar trabajo: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> addTeamMember(int jobId, Map<String, dynamic> data) async {
    final res = await ApiClient.post('/jobs/$jobId/team-members', data);
    if (res.statusCode == 201) return json.decode(res.body);
    throw Exception('Error al agregar colaborador: ${res.statusCode}');
  }

  static Future<void> deleteTeamMember(int jobId, int memberId, String firebaseUid) async {
    final res = await ApiClient.delete('/jobs/$jobId/team-members/$memberId?firebase_uid=$firebaseUid');
    if (res.statusCode != 200) throw Exception('Error al eliminar colaborador: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> addCustomerPayment(int jobId, Map<String, dynamic> data) async {
    final res = await ApiClient.post('/jobs/$jobId/customer-payments', data);
    if (res.statusCode == 201) return json.decode(res.body);
    throw Exception('Error al registrar pago: ${res.statusCode}');
  }

  static Future<void> deleteCustomerPayment(int jobId, int paymentId, String firebaseUid) async {
    final res = await ApiClient.delete('/jobs/$jobId/customer-payments/$paymentId?firebase_uid=$firebaseUid');
    if (res.statusCode != 200) throw Exception('Error al eliminar pago: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> addExpense(int jobId, Map<String, dynamic> data) async {
    final res = await ApiClient.post('/jobs/$jobId/expenses', data);
    if (res.statusCode == 201) return json.decode(res.body);
    throw Exception('Error al registrar gasto: ${res.statusCode}');
  }

  static Future<void> deleteExpense(int jobId, int expenseId, String firebaseUid) async {
    final res = await ApiClient.delete('/jobs/$jobId/expenses/$expenseId?firebase_uid=$firebaseUid');
    if (res.statusCode != 200) throw Exception('Error al eliminar gasto: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> addTeamMemberPayment(int jobId, Map<String, dynamic> data) async {
    final res = await ApiClient.post('/jobs/$jobId/team-member-payments', data);
    if (res.statusCode == 201) return json.decode(res.body);
    throw Exception('Error al registrar pago: ${res.statusCode}');
  }

  static Future<void> deleteTeamMemberPayment(int jobId, int paymentId, String firebaseUid) async {
    final res = await ApiClient.delete('/jobs/$jobId/team-member-payments/$paymentId?firebase_uid=$firebaseUid');
    if (res.statusCode != 200) throw Exception('Error al eliminar pago: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> getFinancialSummary(int jobId, String firebaseUid) async {
    final res = await ApiClient.get('/jobs/$jobId/financial-summary?firebase_uid=$firebaseUid');
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error al cargar resumen: ${res.statusCode}');
  }
}
