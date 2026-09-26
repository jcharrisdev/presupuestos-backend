/**
 * routes/calendario.js — Eventos de calendario (pagos/cobros con fecha fija).
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { generarEventosCalendario } = require('../lib/calendario_helpers');

router.get('/calendario/eventos', async (req, res) => {
  const { firebase_uid, mes, anio } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    // J3: el vínculo con el gasto fijo/deuda que generó el evento ya existe en
    // BD (user_gasto_fijo_id, deuda_id) pero era invisible para el usuario —
    // se trae el nombre para poder mostrarlo y enlazar de vuelta al origen.
    let sql = `SELECT ce.*, g.tipo AS gasto_tipo,
                      gf.descripcion AS fijo_nombre, d.nombre AS deuda_nombre
               FROM calendario_eventos ce
               LEFT JOIN gastos g ON ce.gasto_id = g.id
               LEFT JOIN user_gastos_fijos gf ON ce.user_gasto_fijo_id = gf.id
               LEFT JOIN deudas d ON ce.deuda_id = d.id
               WHERE ce.firebase_uid = ?`;
    const params = [firebase_uid];
    if (mes && anio) {
      sql += ` AND YEAR(ce.fecha_evento) = ? AND MONTH(ce.fecha_evento) = ?`;
      params.push(anio, mes);
    }
    sql += ` ORDER BY ce.fecha_evento ASC`;
    const [eventos] = await db.execute(sql, params);
    res.json(eventos);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /calendario/generar
 * Genera manualmente los eventos de calendario para un gasto ya existente.
 * Útil si el usuario cambia un gasto a tipo_fecha='fija' después de crearlo.
 */
router.post('/calendario/generar', async (req, res) => {
  const { gasto_id, firebase_uid } = req.body;
  if (!gasto_id || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [[gasto]] = await db.execute(
      `SELECT id FROM gastos WHERE id = ? AND firebase_uid = ?`,
      [gasto_id, firebase_uid]
    );
    if (!gasto) return res.status(404).json({ error: 'Gasto no encontrado' });
    const count = await generarEventosCalendario(gasto_id, firebase_uid);
    res.json({ message: `${count} eventos generados`, count });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * PUT /calendario/eventos/:id/estado
 * Actualiza el estado de un evento: 'pendiente' | 'pagado' | 'vencido'.
 * Se llama cuando el usuario marca un pago desde la pantalla del calendario.
 */
router.put('/calendario/eventos/:id/estado', async (req, res) => {
  const { id } = req.params;
  let { estado, firebase_uid } = req.body;
  if (!estado || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  if (!['pendiente', 'pagado', 'vencido', 'cobrado'].includes(estado))
    return res.status(400).json({ error: 'Estado inválido' });
  // El ENUM de calendario_eventos solo acepta ('pendiente','pagado','vencido').
  // Versiones anteriores del app enviaban 'cobrado' → mapear a 'pagado' para
  // evitar WARN_DATA_TRUNCATED de MySQL sin requerir migración de schema.
  if (estado === 'cobrado') estado = 'pagado';
  try {
    const [result] = await db.execute(
      `UPDATE calendario_eventos SET estado = ? WHERE id = ? AND firebase_uid = ?`,
      [estado, id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Evento no encontrado' });
    res.json({ message: 'Estado actualizado', estado });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * DELETE /calendario/eventos/:id?firebase_uid=&solo_este=true|false
 * Elimina un evento del calendario.
 * solo_este=true  → solo elimina este evento específico
 * solo_este=false → elimina este y todos los futuros del mismo gasto
 *   (útil cuando el usuario cancela un gasto recurrente)
 */
router.delete('/calendario/eventos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, solo_este } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    let sql, params;
    if (solo_este === 'false') {
      // Eliminar este y todos los eventos futuros del mismo gasto
      const [[ev]] = await db.execute(
        `SELECT gasto_id, fecha_evento FROM calendario_eventos WHERE id = ?`, [id]
      );
      if (!ev) return res.status(404).json({ error: 'Evento no encontrado' });
      const fechaStr = ev.fecha_evento instanceof Date
        ? ev.fecha_evento.toISOString().split('T')[0]
        : String(ev.fecha_evento).split('T')[0];
      sql    = `DELETE FROM calendario_eventos WHERE gasto_id = ? AND firebase_uid = ? AND fecha_evento >= ?`;
      params = [ev.gasto_id, firebase_uid, fechaStr];
    } else {
      sql    = `DELETE FROM calendario_eventos WHERE id = ? AND firebase_uid = ?`;
      params = [id, firebase_uid];
    }
    const [result] = await db.execute(sql, params);
    res.json({ message: `${result.affectedRows} evento(s) eliminado(s)` });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
