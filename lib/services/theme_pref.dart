// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../theme/app_theme.dart';

/// Carga y guarda la preferencia de tema (claro/oscuro) en localStorage.
/// Web-only por ahora (la app corre en web; el APK persistiría en backend).
class ThemePref {
  static const _key = 'salarying_tema';

  /// Llamar en main() antes de runApp para aplicar el tema guardado.
  static void load() {
    final v = html.window.localStorage[_key];
    AppTheme.setMode(v != 'light'); // default oscuro
  }

  /// Cambia el tema y lo persiste.
  static void set(bool dark) {
    AppTheme.setMode(dark);
    html.window.localStorage[_key] = dark ? 'dark' : 'light';
  }
}
