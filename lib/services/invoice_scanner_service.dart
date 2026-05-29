import 'dart:convert';
import 'api_client.dart';

class InvoiceScannerService {
  static Future<Map<String, dynamic>> processQrScan(
      String qrContent, String firebaseUid) async {
    final resp = await ApiClient.post('/invoice-scanner/process', {
      'firebase_uid': firebaseUid,
      'qr_content': qrContent,
    });
    if (resp.statusCode == 201 || resp.statusCode == 200) {
      return json.decode(resp.body);
    }
    final err = json.decode(resp.body);
    throw Exception(err['error'] ?? 'Error al procesar QR');
  }

  static Future<List<dynamic>> listInvoices(
    String firebaseUid, {
    String? status,
    String? dateFrom,
    String? dateTo,
    String? merchant,
  }) async {
    String path = '/invoice-scanner/invoices?firebase_uid=$firebaseUid';
    if (status != null)   path += '&status=$status';
    if (dateFrom != null) path += '&date_from=$dateFrom';
    if (dateTo != null)   path += '&date_to=$dateTo';
    if (merchant != null) path += '&merchant=${Uri.encodeComponent(merchant)}';

    final resp = await ApiClient.get(path);
    if (resp.statusCode == 200) return json.decode(resp.body);
    final err = json.decode(resp.body);
    throw Exception(err['error'] ?? 'Error al listar facturas');
  }

  static Future<Map<String, dynamic>> getInvoiceDetail(
      int id, String firebaseUid) async {
    final resp = await ApiClient.get(
        '/invoice-scanner/invoices/$id?firebase_uid=$firebaseUid');
    if (resp.statusCode == 200) return json.decode(resp.body);
    final err = json.decode(resp.body);
    throw Exception(err['error'] ?? 'Error al obtener factura');
  }

  static Future<Map<String, dynamic>> assignInvoice(
      int id, Map<String, dynamic> assignment, String firebaseUid) async {
    final resp = await ApiClient.post(
      '/invoice-scanner/invoices/$id/assign',
      {...assignment, 'firebase_uid': firebaseUid},
    );
    if (resp.statusCode == 201 || resp.statusCode == 200) {
      return json.decode(resp.body);
    }
    final err = json.decode(resp.body);
    throw Exception(err['error'] ?? 'Error al asignar factura');
  }

  static Future<void> removeAssignment(
      int invoiceId, int assignmentId, String firebaseUid) async {
    final resp = await ApiClient.delete(
        '/invoice-scanner/invoices/$invoiceId/assignments/$assignmentId?firebase_uid=$firebaseUid');
    if (resp.statusCode != 200) {
      final err = json.decode(resp.body);
      throw Exception(err['error'] ?? 'Error al eliminar asignación');
    }
  }

  static Future<void> deleteInvoice(int id, String firebaseUid) async {
    final resp = await ApiClient.delete(
        '/invoice-scanner/invoices/$id?firebase_uid=$firebaseUid');
    if (resp.statusCode != 200) {
      final err = json.decode(resp.body);
      throw Exception(err['error'] ?? 'Error al eliminar factura');
    }
  }

  static Future<Map<String, dynamic>> updateInvoiceManual(
      int id, Map<String, dynamic> data, String firebaseUid) async {
    final resp = await ApiClient.patch(
      '/invoice-scanner/invoices/$id',
      {...data, 'firebase_uid': firebaseUid},
    );
    if (resp.statusCode == 200) return json.decode(resp.body);
    final err = json.decode(resp.body);
    throw Exception(err['error'] ?? 'Error al actualizar factura');
  }

  static Future<Map<String, dynamic>> registrarEnMes(
    int id,
    String firebaseUid, {
    required String categoria,
    required String tipo,
    required String nombreGasto,
    required String fecha,
  }) async {
    final resp = await ApiClient.post(
      '/invoice-scanner/$id/registrar-en-mes',
      {
        'firebase_uid': firebaseUid,
        'categoria':    categoria,
        'tipo':         tipo,
        'nombre_gasto': nombreGasto,
        'fecha_override': fecha,
      },
    );
    if (resp.statusCode == 201 || resp.statusCode == 200) {
      return json.decode(resp.body);
    }
    final err = json.decode(resp.body);
    throw Exception(err['error'] ?? 'Error al registrar factura en el mes');
  }

  static Future<List<dynamic>> getLogs(int id, String firebaseUid) async {
    final resp = await ApiClient.get(
        '/invoice-scanner/invoices/$id/logs?firebase_uid=$firebaseUid');
    if (resp.statusCode == 200) return json.decode(resp.body);
    return [];
  }
}
