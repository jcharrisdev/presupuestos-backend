import 'dart:convert';
import 'services/api_client.dart';

class PresupuestoService {
  Future<List<dynamic>> obtenerPresupuestos(String firebaseUid) async {
    final response = await ApiClient.get('/presupuestos?firebase_uid=$firebaseUid');
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Error al obtener los presupuestos (${response.statusCode})');
  }
}
