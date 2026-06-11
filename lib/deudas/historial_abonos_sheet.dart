import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../utils/money.dart';

class HistorialAbonosSheet {
  static void show(
    BuildContext context, {
    required int deudaId,
    required String deudaNombre,
    required String firebaseUid,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _HistorialBody(
        deudaId: deudaId,
        deudaNombre: deudaNombre,
        firebaseUid: firebaseUid,
      ),
    );
  }
}

class _HistorialBody extends StatefulWidget {
  final int deudaId;
  final String deudaNombre;
  final String firebaseUid;
  const _HistorialBody({
    required this.deudaId,
    required this.deudaNombre,
    required this.firebaseUid,
  });
  @override
  State<_HistorialBody> createState() => _HistorialBodyState();
}

class _HistorialBodyState extends State<_HistorialBody> {
  List<Map<String, dynamic>> _abonos = [];
  double _totalAbonado = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get(
          '/deudas/${widget.deudaId}/abonos?firebase_uid=${widget.firebaseUid}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (mounted) setState(() {
          _abonos = (data['abonos'] as List).cast<Map<String, dynamic>>();
          _totalAbonado = double.tryParse(data['total_abonado'].toString()) ?? 0;
          _loading = false;
        });
      } else {
        if (mounted) setState(() {
          _error = jsonDecode(res.body)['error']?.toString() ?? 'Error';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Column(children: [
        // Handle + header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Historial de abonos',
                    style: const TextStyle(color: AppTheme.textPrimary,
                        fontSize: 17, fontWeight: FontWeight.w700)),
                Text(widget.deudaNombre,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ])),
              if (!_loading && _abonos.isNotEmpty)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${Money.fmt(_totalAbonado)}',
                      style: const TextStyle(color: AppTheme.success,
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const Text('total abonado',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                ]),
            ]),
            const SizedBox(height: 12),
            const Divider(color: AppTheme.border, height: 1),
          ]),
        ),
        // Body
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _error != null
                  ? Center(child: Text(_error!,
                        style: const TextStyle(color: AppTheme.danger, fontSize: 13)))
                  : _abonos.isEmpty
                      ? const Center(child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.history, color: AppTheme.textMuted, size: 40),
                            SizedBox(height: 12),
                            Text('Aún no hay abonos registrados',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                          ]),
                        ))
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          itemCount: _abonos.length,
                          separatorBuilder: (_, __) =>
                              const Divider(color: AppTheme.border, height: 1),
                          itemBuilder: (_, i) {
                            final a = _abonos[i];
                            final monto = double.tryParse(a['monto'].toString()) ?? 0.0;
                            final fecha = (a['fecha'] as String? ?? '').substring(0, 10);
                            final nombre = a['nombre'] as String? ?? 'Abono';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.success.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.payments_outlined,
                                      color: AppTheme.success, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(nombre,
                                      style: const TextStyle(color: AppTheme.textPrimary,
                                          fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text(fecha,
                                      style: const TextStyle(
                                          color: AppTheme.textMuted, fontSize: 11)),
                                ])),
                                Text('${Money.fmt(monto)}',
                                    style: const TextStyle(color: AppTheme.success,
                                        fontSize: 14, fontWeight: FontWeight.w700)),
                              ]),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
