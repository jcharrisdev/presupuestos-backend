import 'dart:convert';
import 'api_client.dart';

class SalesService {
  static Future<List<Map<String, dynamic>>> getVentas(String uid) async {
    final res = await ApiClient.get('/ventas?firebase_uid=$uid');
    if (res.statusCode == 200) {
      return (json.decode(res.body) as List).cast<Map<String, dynamic>>();
    }
    throw Exception('Error al obtener ventas (${res.statusCode})');
  }

  static Future<Map<String, dynamic>> getVentaDetalle(int id, String uid) async {
    final res = await ApiClient.get('/ventas/$id?firebase_uid=$uid');
    if (res.statusCode == 200) return json.decode(res.body) as Map<String, dynamic>;
    throw Exception('Error al obtener detalle de venta (${res.statusCode})');
  }

  static Future<void> cobrarCliente(int cobroId, Map<String, dynamic> body) async {
    final res = await ApiClient.put('/cobros/$cobroId/cobrar', body);
    if (res.statusCode != 200) throw Exception('Error al cobrar (${res.statusCode})');
  }

  static Future<void> deleteVenta(int id, String uid) async {
    final res = await ApiClient.delete('/ventas/$id?firebase_uid=$uid');
    if (res.statusCode != 200) throw Exception('Error al eliminar venta (${res.statusCode})');
  }
}
