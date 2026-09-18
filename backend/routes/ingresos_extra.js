/**
 * routes/ingresos_extra.js — MÓDULO: INGRESOS EXTRA (fotografía, freelance, bonos, regalos, etc.)
 * Los ingresos extra se suman al ingreso_real del mes correspondiente.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { _logInfo } = require('../lib/logger');

// Helper: recalcula ingreso_real del mes = salario base + suma de ingresos extra
async function _recalcularIngresoRealMes(firebase_uid, anio, mes) {
  const [[income]] = await db.execute(
    `SELECT ingreso_neto_mensual FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
  );
  const base = income ? Number(income.ingreso_neto_mensual) : 0;
  const [[extra]] = await db.execute(
    `SELECT COALESCE(SUM(monto), 0) AS total FROM registros_ingreso
     WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
    [firebase_uid, anio, mes]
  );
  const totalExtra = Number(extra.total);
  const ingresoReal = parseFloat((base + totalExtra).toFixed(2));
  await db.execute(
    `UPDATE meses_financieros SET ingreso_real = ?
     WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
    [ingresoReal, firebase_uid, anio, mes]
  );
}

// GET /user/ingresos-extra?firebase_uid=&anio=&mes=
router.get('/user/ingresos-extra', async (req, res) => {
  const { firebase_uid, anio, mes } = req.query;
  if (!firebase_uid || !anio || !mes) return res.status(400).json({ error: 'firebase_uid, anio y mes requeridos' });
  try {
    const [rows] = await db.execute(
      `SELECT * FROM registros_ingreso
       WHERE firebase_uid = ? AND anio = ? AND mes = ?
       ORDER BY fecha DESC, created_at DESC`,
      [firebase_uid, anio, mes]
    );
    const total = rows.reduce((s, r) => s + Number(r.monto), 0);
    // Agrupar por fuente para la vista bucket
    const buckets = {};
    for (const r of rows) {
      if (!buckets[r.fuente_nombre]) buckets[r.fuente_nombre] = { fuente_nombre: r.fuente_nombre, total: 0, registros: [] };
      buckets[r.fuente_nombre].total += Number(r.monto);
      buckets[r.fuente_nombre].registros.push(r);
    }
    res.json({
      ingresos: rows,
      total: parseFloat(total.toFixed(2)),
      buckets: Object.values(buckets).map(b => ({ ...b, total: parseFloat(b.total.toFixed(2)) })),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/ingresos-extra
router.post('/user/ingresos-extra', async (req, res) => {
  const { firebase_uid, monto, descripcion, fuente_nombre, fecha } = req.body;
  if (!firebase_uid || !monto || !fuente_nombre || !fecha)
    return res.status(400).json({ error: 'firebase_uid, monto, fuente_nombre y fecha requeridos' });
  if (Number(monto) <= 0) return res.status(400).json({ error: 'monto debe ser mayor a 0' });
  try {
    const d = new Date(fecha);
    const anio = d.getFullYear();
    const mes  = d.getMonth() + 1;
    const [result] = await db.execute(
      `INSERT INTO registros_ingreso (firebase_uid, monto, descripcion, fuente_nombre, fecha, anio, mes)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, Number(monto).toFixed(2), descripcion || null, fuente_nombre, fecha, anio, mes]
    );
    await _recalcularIngresoRealMes(firebase_uid, anio, mes);
    const [[saved]] = await db.execute(`SELECT * FROM registros_ingreso WHERE id = ?`, [result.insertId]);
    _logInfo('/user/ingresos-extra', `Ingreso extra registrado: $${Number(monto).toFixed(2)} (${fuente_nombre})`, firebase_uid);
    res.status(201).json(saved);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /user/ingresos-extra/:id
router.delete('/user/ingresos-extra/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[row]] = await db.execute(
      `SELECT * FROM registros_ingreso WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!row) return res.status(404).json({ error: 'Ingreso no encontrado' });
    await db.execute(`DELETE FROM registros_ingreso WHERE id = ?`, [id]);
    await _recalcularIngresoRealMes(firebase_uid, row.anio, row.mes);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
