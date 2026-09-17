import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Aviso único para acciones del usuario que fallaron y antes se ignoraban
/// en silencio (X1). Muestra un snackbar discreto — nunca bloquea la pantalla.
class ErrorFeedback {
  static void mostrar(BuildContext context, String mensaje) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: AppTheme.danger),
    );
  }
}
