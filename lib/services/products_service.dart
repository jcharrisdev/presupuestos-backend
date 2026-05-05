import 'dart:convert';
import 'api_client.dart';

class ProductsService {
  static Future<List<Map<String, dynamic>>> getProductos(String uid) async {
    final res = await ApiClient.get('/productos?firebase_uid=$uid');
    if (res.statusCode == 200) {
      return (json.decode(res.body) as List).cast<Map<String, dynamic>>();
    }
    throw Exception('Error al obtener productos (${res.statusCode})');
  }

  static Future<List<Map<String, dynamic>>> getVariantes(int productoId, String uid) async {
    final res = await ApiClient.get('/productos/$productoId/variantes?firebase_uid=$uid');
    if (res.statusCode == 200) {
      return (json.decode(res.body) as List).cast<Map<String, dynamic>>();
    }
    throw Exception('Error al obtener variantes (${res.statusCode})');
  }

  static Future<void> deleteProducto(int id, String uid) async {
    final res = await ApiClient.delete('/productos/$id?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception('Error al eliminar producto (${res.statusCode})');
  }
}
