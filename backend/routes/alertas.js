/**
 * routes/alertas.js — Alertas financieras inteligentes: lectura, generación
 * manual y resumen por mes. La generación en sí vive en lib/mes_helpers.js
 * (_generarAlertasMes), compartida con Gastos, Gustitos, Eventos y Deudas.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { _generarAlertasMes } = require('../lib/mes_helpers');

router.get('/user/alertas', async (req, res) => {
  const { firebase_uid, anio, mes, leidas } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    let sql = `SELECT * FROM alertas_financieras WHERE firebase_uid = ?`;
    const params = [firebase_uid];
    if (anio)   { sql += ` AND anio = ?`;  params.push(anio); }
    if (mes)    { sql += ` AND mes = ?`;   params.push(mes); }
    if (leidas !== undefined) { sql += ` AND leida = ?`; params.push(leidas === '1' ? 1 : 0); }
    sql += ` ORDER BY created_at DESC LIMIT 50`;
    const [rows] = await db.execute(sql, params);
    res.json({ alertas: rows, total: rows.length, no_leidas: rows.filter(a => !a.leida).length });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/alertas/generar/:anio/:mes
router.post('/user/alertas/generar/:anio/:mes', async (req, res) => {
  const { anio, mes } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const alertas = await _generarAlertasMes(firebase_uid, Number(anio), Number(mes));
    res.json({ alertas_generadas: alertas.length, alertas });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PATCH /user/alertas/:id/leer
router.patch('/user/alertas/:id/leer', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(`UPDATE alertas_financieras SET leida = 1 WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/alertas/resumen?firebase_uid=&anio=
// Devuelve conteo de alertas no leídas por mes del año (para badges en el grid).
router.get('/user/alertas/resumen', async (req, res) => {
  const { firebase_uid, anio } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT mes,
              COUNT(*) AS total,
              SUM(CASE WHEN leida = 0 THEN 1 ELSE 0 END) AS no_leidas,
              SUM(CASE WHEN nivel = 'danger' AND leida = 0 THEN 1 ELSE 0 END) AS peligro,
              SUM(CASE WHEN nivel = 'warning' AND leida = 0 THEN 1 ELSE 0 END) AS advertencia
       FROM alertas_financieras
       WHERE firebase_uid = ? AND anio = ?
       GROUP BY mes ORDER BY mes ASC`,
      [firebase_uid, anio || new Date().getFullYear()]
    );
    // Convertir a mapa mes→conteos
    const porMes = {};
    for (const r of rows) {
      porMes[Number(r.mes)] = {
        total:       Number(r.total),
        no_leidas:   Number(r.no_leidas),
        peligro:     Number(r.peligro),
        advertencia: Number(r.advertencia),
      };
    }
    res.json({ anio: Number(anio || new Date().getFullYear()), por_mes: porMes });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
