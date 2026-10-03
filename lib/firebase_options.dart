// Configuración de Firebase para esta app — solo plataforma Web, ya que
// Salarying se despliega únicamente como Flutter Web (ver CLAUDE.md).
// Generado a mano a partir del config del proyecto Firebase "salary-bi"
// (valores públicos del cliente, no secretos — van en el bundle del navegador).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'DefaultFirebaseOptions solo está configurado para Web — '
      'Salarying no se distribuye en ${defaultTargetPlatform.name}.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB_8Nq2ZvHUq98UgK3KXmMaUOlJQhnN_aw',
    appId: '1:750057422826:web:567c937283dc0969a4fc93',
    messagingSenderId: '750057422826',
    projectId: 'salary-bi',
    authDomain: 'salary-bi.firebaseapp.com',
    storageBucket: 'salary-bi.firebasestorage.app',
    measurementId: 'G-6H6M59LKRT',
  );
}
