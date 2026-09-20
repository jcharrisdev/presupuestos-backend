import 'dart:convert';
import 'api_client.dart';

class RegistrosService {
  static Future<Map<String, dynamic>> getRegistros(
    String uid, int anio, int mes, {String? tipo, String? categoria}
  ) async {
    var path = '/registros/$anio/$mes?firebase_uid=$uid';
    if (tipo != null) path += '&tipo=$tipo';
    if (categoria != null) path += '&categoria=$categoria';
    final res = await ApiClient.get(path);
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> crear({
    required String uid,
    required int anio,
    required int mes,
    required String tipo,
    required String categoria,
    required String nombre,
    required double monto,
    required String fecha,
    String? subcategoriaId,
    String? notas,
    int? origenFijoId,
    int? origenVariableId,
    int? origenDeudaId,
    int? definitionId,
    int pagado = 0,
  }) async {
    final res = await ApiClient.post('/registros', {
      'firebase_uid': uid,
      'anio': anio,
      'mes': mes,
      'tipo': tipo,
      'categoria': categoria,
      'nombre': nombre,
      'monto': monto,
      'fecha': fecha,
      'pagado': pagado,
      if (subcategoriaId != null) 'subcategoria_id': subcategoriaId,
      if (notas != null) 'notas': notas,
      if (origenFijoId != null) 'origen_fijo_id': origenFijoId,
      if (origenVariableId != null) 'origen_variable_id': origenVariableId,
      if (origenDeudaId != null) 'origen_deuda_id': origenDeudaId,
      if (definitionId != null) 'definition_id': definitionId,
    });
    if (res.statusCode != 201) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> editar(String uid, int id, Map<String, dynamic> data) async {
    final res = await ApiClient.put('/registros/$id', {'firebase_uid': uid, ...data});
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }

  static Future<void> eliminar(String uid, int id) async {
    await ApiClient.delete('/registros/$id?firebase_uid=$uid');
  }

  static Future<void> marcarPagado(String uid, int id, bool pagado) async {
    final res = await ApiClient.patch(
      '/registros/$id/pagar',
      {'firebase_uid': uid, 'pagado': pagado ? 1 : 0},
    );
    if (res.statusCode != 200) {
      var mensaje = 'No se pudo actualizar el estado del gasto';
      try {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic> && body['error'] is String) {
          mensaje = body['error'] as String;
        }
      } catch (_) {
        // El servidor puede responder HTML o texto si el proxy falla.
      }
      throw Exception(mensaje);
    }
  }

  static Future<Map<String, dynamic>> convertirAVariable(String uid, int id, {String frecuencia = 'mensual'}) async {
    final res = await ApiClient.post('/registros/$id/convertir-a-variable', {
      'firebase_uid': uid,
      'frecuencia': frecuencia,
    });
    if (res.statusCode != 201) throw Exception(jsonDecode(res.body)['error'] ?? 'Error');
    return jsonDecode(res.body);
  }
}
