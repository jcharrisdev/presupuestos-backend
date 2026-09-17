/**
 * routes/logs.js — Consulta y limpieza de server_logs (protegido por secret).
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { LOG_SECRET } = require('../lib/logger');

// GET /logs — devuelve los últimos errores del servidor (protegido por secret)
router.get('/logs', async (req, res) => {
  const { secret, limit = 50, nivel, uid, desde } = req.query;
  if (secret !== LOG_SECRET)
    return res.status(401).json({ error: 'Acceso denegado' });
  try {
    let sql = `SELECT id, nivel, ruta, firebase_uid, mensaje, stack, req_body, created_at
               FROM server_logs WHERE 1=1`;
    const params = [];
    if (nivel) { sql += ` AND nivel = ?`; params.push(nivel); }
    if (uid)   { sql += ` AND firebase_uid LIKE ?`; params.push(`%${uid}%`); }
    if (desde) { sql += ` AND created_at >= ?`; params.push(desde); }
    // LIMIT inlined — MySQL 5.6 + mysql2 no acepta BigInt/Number en prepared LIMIT
    const limitInt = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 200);
    sql += ` ORDER BY created_at DESC LIMIT ${limitInt}`;
    const [rows] = await db.execute(sql, params);
    const [[countRow]] = await db.execute(`SELECT COUNT(*) AS total FROM server_logs`);
    const total = Number(countRow.total);
    res.json({ total, mostrados: rows.length, logs: rows });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /logs — limpia los logs (protegido por secret)
router.delete('/logs', async (req, res) => {
  const { secret } = req.query;
  if (secret !== LOG_SECRET) return res.status(401).json({ error: 'Acceso denegado' });
  try {
    await db.execute(`DELETE FROM server_logs WHERE created_at < DATE_SUB(NOW(), INTERVAL 7 DAY)`);
    res.json({ ok: true, mensaje: 'Logs de más de 7 días eliminados' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
