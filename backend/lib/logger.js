/**
 * lib/logger.js — Logging remoto en server_logs (auto-limpieza cada 60 min).
 */
const { db } = require('./db');

const LOG_SECRET = 'salarying_logs_2025';

async function _logError(ruta, error, uid = '-', reqBody = null) {
  try {
    const bodyStr = reqBody ? JSON.stringify(reqBody).substring(0, 1000) : null;
    await db.execute(
      `INSERT INTO server_logs (nivel, ruta, firebase_uid, mensaje, stack, req_body)
       VALUES ('error', ?, ?, ?, ?, ?)`,
      [ruta, uid, error?.message || String(error),
       error?.stack?.substring(0, 2000) || null, bodyStr]
    );
  } catch (_) {}
}

async function _logInfo(ruta, mensaje, uid = '-') {
  try {
    await db.execute(
      `INSERT INTO server_logs (nivel, ruta, firebase_uid, mensaje) VALUES ('info', ?, ?, ?)`,
      [ruta, uid, mensaje]
    );
  } catch (_) {}
}

// Auto-limpieza cada hora — borra todos los logs de más de 60 minutos
setInterval(async () => {
  try {
    await db.execute(`DELETE FROM server_logs WHERE created_at < DATE_SUB(NOW(), INTERVAL 60 MINUTE)`);
  } catch (_) {}
}, 60 * 60 * 1000);

module.exports = { LOG_SECRET, _logError, _logInfo };
