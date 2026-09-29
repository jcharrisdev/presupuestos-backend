import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Antes de editar o eliminar un gasto fijo o variable base, pregunta el
/// alcance del cambio para no reescribir en silencio el presupuesto de un
/// mes que el usuario ya cerró — eso rompería el análisis de desviación
/// ("por qué te desviaste") de ese mes, que se comparó contra un número que
/// ya no sería el mismo.
///
/// Diseño de un toque, no un formulario: la opción segura y recomendada
/// ("Desde ahora") resuelve sin fricción extra. Solo si el usuario elige
/// corregir también el historial se pide una segunda confirmación explícita,
/// porque esa es la acción que puede sorprenderlo después.
///
/// Devuelve `'desde_aqui'`, `'todos'`, o `null` si cancela en cualquier paso.
Future<String?> preguntarAlcanceEdicion(
  BuildContext context, {
  required bool esEliminar,
  String? nombreGasto,
}) async {
  final verbo = esEliminar ? 'eliminar' : 'editar';
  final elegido = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('¿Desde cuándo aplica?', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      content: Text(
        nombreGasto != null
            ? 'Vas a $verbo "$nombreGasto". Los meses que ya cerraste guardan su propio presupuesto, así tu historial no cambia por esto.'
            : 'Los meses que ya cerraste guardan su propio presupuesto, así tu historial no cambia por esto.',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'todos'),
          child: Text(
            esEliminar ? 'Eliminar también de meses pasados' : 'Corregir todo el año',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, 'desde_aqui'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          child: Text('Desde ahora', style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  if (elegido != 'todos') return elegido; // null (canceló) o 'desde_aqui', sin fricción extra

  if (!context.mounted) return null;
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Esto cambia tu historial', style: TextStyle(color: AppTheme.warning, fontSize: 16)),
      content: Text(
        esEliminar
            ? 'Vas a borrar el rastro de este gasto también en los meses que ya cerraste. Úsalo solo si nunca debió estar ahí — no porque ya no lo tengas.'
            : 'Vas a cambiar el presupuesto también de los meses que ya cerraste. Úsalo solo si el número estaba mal desde el principio — no si el gasto cambió con el tiempo.',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Mejor no', style: TextStyle(color: AppTheme.textMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
          child: Text(
            esEliminar ? 'Sí, eliminar de todo el año' : 'Sí, corregir todo el año',
            style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return confirmado == true ? 'todos' : null;
}
