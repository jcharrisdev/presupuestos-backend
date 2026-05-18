import 'dart:convert';
import 'api_client.dart';

class ProductosCatalogoService {
  static Future<List<dynamic>> getAll(String uid, {String? q}) async {
    var url = '/user/productos-catalogo?firebase_uid=$uid';
    if (q != null && q.isNotEmpty) url += '&q=${Uri.encodeComponent(q)}';
    final res = await ApiClient.get(url);
    if (res.statusCode == 200) return json.decode(res.body) as List;
    return [];
  }

  static Future<Map<String, dynamic>?> getHistorial(int productoId, String uid) async {
    final res = await ApiClient.get('/user/productos-catalogo/$productoId/historial?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body);
    return null;
  }

  static Future<bool> setCategoria(int productoId, String uid, String? categoria) async {
    final res = await ApiClient.patch(
      '/user/productos-catalogo/$productoId',
      {'firebase_uid': uid, 'categoria': categoria},
    );
    return res.statusCode == 200;
  }

  static Future<Map<String, dynamic>?> registrarEnMes(
    int invoiceId,
    String uid, {
    String categoria = 'Compras',
    String? nombreGasto,
  }) async {
    final body = <String, dynamic>{
      'firebase_uid': uid,
      'categoria': categoria,
      if (nombreGasto != null) 'nombre_gasto': nombreGasto,
    };
    final res = await ApiClient.post('/invoice-scanner/$invoiceId/registrar-en-mes', body);
    if (res.statusCode == 201) return json.decode(res.body);
    final err = json.decode(res.body);
    throw Exception(err['error'] ?? 'Error al registrar');
  }
}
