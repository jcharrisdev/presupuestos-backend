import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/eventos_service.dart';
import '../widgets/financiero/mes_rango_selector.dart';

class CrearEventoSheet extends StatefulWidget {
  final String firebaseUid;
  final int anio;
  final Map<String, dynamic>? eventoExistente;

  const CrearEventoSheet({
    Key? key,
    required this.firebaseUid,
    required this.anio,
    this.eventoExistente,
  }) : super(key: key);

  @override
  State<CrearEventoSheet> createState() => _CrearEventoSheetState();
}

class _CrearEventoSheetState extends State<CrearEventoSheet> {
  final _formKey  = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _montoCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();

  int _mesInicio = DateTime.now().month;
  int _mesFin    = DateTime.now().month;
  String _emoji  = '🎯';
  bool _guardando = false;

  static const _emojis = ['🎯', '✈️', '🎂', '💍', '🎄', '🏠', '🚗', '📱', '🏖️', '🎓', '🏥', '🎁'];
  static const _mesesLabel = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  bool get _esEdicion => widget.eventoExistente != null;

  @override
  void initState() {
    super.initState();
    final e = widget.eventoExistente;
    if (e != null) {
      _nombreCtrl.text = e['nombre'] as String? ?? '';
      _montoCtrl.text  = (e['monto_total'] as num).toStringAsFixed(2);
      _descCtrl.text   = e['descripcion'] as String? ?? '';
      _emoji           = e['emoji'] as String? ?? '🎯';
      _mesInicio       = e['mes_inicio'] as int;
      _mesFin          = e['mes_fin'] as int;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _montoCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  double get _cuotaMensual {
    final monto = double.tryParse(_montoCtrl.text) ?? 0.0;
    final meses = _mesFin - _mesInicio + 1;
    return meses > 0 ? monto / meses : monto;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final body = {
        'nombre':     _nombreCtrl.text.trim(),
        'monto_total': double.parse(_montoCtrl.text),
        'anio':       widget.anio,
        'mes_inicio': _mesInicio,
        'mes_fin':    _mesFin,
        'descripcion': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'emoji':      _emoji,
      };
      if (_esEdicion) {
        await EventosService.editarEvento(widget.firebaseUid, widget.eventoExistente!['id'] as int, body);
      } else {
        await EventosService.crearEvento(widget.firebaseUid, body);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cuota  = _cuotaMensual;
    final meses  = _mesFin - _mesInicio + 1;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),

              // Título
              Text(_esEdicion ? 'Editar evento' : 'Nuevo evento',
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Selector de emoji
              const Text('Ícono', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _emojis.map((em) => GestureDetector(
                    onTap: () => setState(() => _emoji = em),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _emoji == em ? AppTheme.primary.withOpacity(0.15) : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _emoji == em ? AppTheme.primary : AppTheme.border,
                            width: _emoji == em ? 1.5 : 1),
                      ),
                      child: Text(em, style: const TextStyle(fontSize: 22)),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Nombre
              TextFormField(
                controller: _nombreCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _dec('Nombre del evento', hint: 'Ej: Vacaciones, Boda de Ana...'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              // Monto total
              TextFormField(
                controller: _montoCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _dec('Presupuesto total (\$)', hint: '0.00'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if ((double.tryParse(v) ?? 0) <= 0) return 'Debe ser mayor a 0';
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              // Rango de meses
              const Text('Período del evento', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              MesRangoSelector(
                mesInicio: _mesInicio,
                mesFin: _mesFin,
                onChange: (ini, fin) => setState(() { _mesInicio = ini; _mesFin = fin; }),
              ),
              const SizedBox(height: 12),

              // Descripción
              TextFormField(
                controller: _descCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _dec('Descripción (opcional)', hint: 'Notas sobre el evento...'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Preview cuota
              if (_montoCtrl.text.isNotEmpty && double.tryParse(_montoCtrl.text) != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Cuota mensual',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                        Text('\$${cuota.toStringAsFixed(2)}/mes',
                            style: const TextStyle(
                                color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        const Text('Durante',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                        Text(
                          meses == 1
                              ? _mesesLabel[_mesInicio]
                              : '$meses meses (${_mesesLabel[_mesInicio]}–${_mesesLabel[_mesFin]})',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ]),
                    ],
                  ),
                ),
              const SizedBox(height: 20),

              // Botón
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _guardando
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(_esEdicion ? 'Guardar cambios' : 'Crear evento',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: AppTheme.textSecondary),
    hintStyle: const TextStyle(color: AppTheme.textMuted),
    filled: true,
    fillColor: AppTheme.surfaceAlt,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.border)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.border)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primary)),
  );
}
