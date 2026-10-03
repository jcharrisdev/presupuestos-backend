/**
 * lib/push_notifications.js — Notificaciones push vía Firebase Cloud Messaging.
 *
 * Catálogo deliberadamente corto (ver SALARYING_MEJORAS.md): solo se empuja lo
 * urgente y accionable *hoy* (pago vencido, recordatorio de pago, mes que entra
 * en rojo). Todo lo demás (tendencias, DTI, categorías excedidas) se queda como
 * insight pasivo dentro de la app — empujarlo al teléfono sería ruido, no ayuda.
 *
 * Disparo por cambio de estado, no por persistencia: `notificaciones_enviadas`
 * garantiza una sola notificación por ocurrencia (no repetir mientras la alerta
 * siga siendo cierta), para no entrenar al usuario a ignorar la app.
 *
 * Copy sin cifras ni tono acusador — validado con el skill asesor-financiero-salarying:
 * el usuario puede ver el push en la pantalla de bloqueo, sin contexto, y ya le
 * teme a sus números.
 */
const { db } = require('./db');

let adminApp = null;
function _getAdmin() {
  if (adminApp !== null) return adminApp;
  const { FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY } = process.env;
  if (!FIREBASE_PROJECT_ID || !FIREBASE_CLIENT_EMAIL || !FIREBASE_PRIVATE_KEY) {
    adminApp = false; // credenciales no configuradas — push deshabilitado
    return adminApp;
  }
  try {
    const admin = require('firebase-admin');
    adminApp = admin.apps.length ? admin.app() : admin.initializeApp({
      credential: admin.credential.cert({
        projectId: FIREBASE_PROJECT_ID,
        clientEmail: FIREBASE_CLIENT_EMAIL,
        privateKey: FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
      }),
    });
  } catch (e) {
    console.error('Error inicializando firebase-admin:', e.message);
    adminApp = false;
  }
  return adminApp;
}

async function _registrarToken(firebase_uid, token, plataforma = 'web') {
  await db.execute(
    `INSERT INTO device_tokens (firebase_uid, token, plataforma, updated_at)
     VALUES (?, ?, ?, NOW())
     ON DUPLICATE KEY UPDATE firebase_uid = VALUES(firebase_uid), plataforma = VALUES(plataforma), updated_at = NOW()`,
    [firebase_uid, token, plataforma]
  );
}

async function _eliminarToken(token) {
  await db.execute(`DELETE FROM device_tokens WHERE token = ?`, [token]);
}

// Envía un push solo si esta (firebase_uid, tipo, referencia_id) nunca se envió.
// Devuelve true si se envió, false si ya existía o no hay tokens/credenciales.
async function _enviarPushSiNueva(firebase_uid, tipo, referencia_id, titulo, cuerpo) {
  try {
    await db.execute(
      `INSERT INTO notificaciones_enviadas (firebase_uid, tipo, referencia_id) VALUES (?, ?, ?)`,
      [firebase_uid, tipo, referencia_id]
    );
  } catch (e) {
    if (e.code === 'ER_DUP_ENTRY') return false; // ya se envió antes — no repetir
    throw e;
  }

  const admin = _getAdmin();
  if (!admin) return false; // credenciales no configuradas

  const [tokens] = await db.execute(
    `SELECT token FROM device_tokens WHERE firebase_uid = ?`, [firebase_uid]
  );
  if (!tokens.length) return false;

  try {
    const resp = await admin.messaging().sendEachForMulticast({
      tokens: tokens.map(t => t.token),
      notification: { title: titulo, body: cuerpo },
    });
    const invalidos = [];
    resp.responses.forEach((r, i) => {
      if (!r.success && ['messaging/invalid-registration-token', 'messaging/registration-token-not-registered']
          .includes(r.error?.code)) {
        invalidos.push(tokens[i].token);
      }
    });
    for (const t of invalidos) await _eliminarToken(t);
    return true;
  } catch (e) {
    console.error('Error enviando push:', e.message);
    return false;
  }
}

module.exports = { _registrarToken, _eliminarToken, _enviarPushSiNueva };
