import 'dart:convert';
import 'package:http/http.dart' as http;

class PresupuestoService {
  final String baseUrl =
      'https://presupuestos-backend-h3l6.onrender.com';

  // Obtener presupuestos por usuario (firebaseUid = email por ahora)
  Future<List<dynamic>> obtenerPresupuestos(String firebaseUid) async {
    final url = Uri.parse(
      '$baseUrl/presupuestos?firebase_uid=$firebaseUid',
    );

    print('URL final: $url');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception(
          'Error al obtener los presupuestos (${response.statusCode})');
    }
  }
}
