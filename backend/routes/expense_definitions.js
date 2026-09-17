/**
 * routes/expense_definitions.js — Plantillas de gasto reutilizables (expense_definitions).
 * Evitan reescribir el mismo gasto cada mes; al registrar un gasto se vincula
 * automáticamente a su definición.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');

// GET /user/expense-definitions?firebase_uid=
// Devuelve las definiciones activas del usuario con el último monto usado.
router.get('/user/expense-definitions', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // O5 — recencia: devolver fecha de último uso y ordenar por más reciente.
    // Los que nunca se han registrado (created_at NULL) quedan al final.
    const [rows] = await db.execute(
      `SELECT ed.*,
              rg.monto      AS ultimo_monto,
              rg.anio       AS ultimo_anio,
              rg.mes        AS ultimo_mes,
              rg.fecha      AS ultimo_fecha,
              rg.created_at AS ultimo_created
       FROM expense_definitions ed
       LEFT JOIN registros_gasto rg ON rg.definition_id = ed.id
         AND rg.created_at = (
           SELECT MAX(r2.created_at) FROM registros_gasto r2
           WHERE r2.definition_id = ed.id AND r2.firebase_uid = ed.firebase_uid
         )
       WHERE ed.firebase_uid = ? AND ed.activo = 1
       ORDER BY rg.created_at IS NULL ASC, rg.created_at DESC, ed.nombre ASC`,
      [firebase_uid]
    );
    res.json(rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/expense-definitions
// Crea una definición manualmente.
router.post('/user/expense-definitions', async (req, res) => {
  const { firebase_uid, nombre, categoria, tipo_habitual = 'variable' } = req.body;
  if (!firebase_uid || !nombre || !categoria)
    return res.status(400).json({ error: 'firebase_uid, nombre y categoria requeridos' });
  try {
    // Evitar duplicados por nombre+categoria para el mismo usuario
    const [[existing]] = await db.execute(
      `SELECT id FROM expense_definitions WHERE firebase_uid = ? AND nombre = ? AND categoria = ? AND activo = 1`,
      [firebase_uid, nombre.trim(), categoria]
    );
    if (existing) return res.json(existing);
    const [r] = await db.execute(
      `INSERT INTO expense_definitions (firebase_uid, nombre, categoria, tipo_habitual)
       VALUES (?, ?, ?, ?)`,
      [firebase_uid, nombre.trim(), categoria, tipo_habitual]
    );
    const [[created]] = await db.execute(`SELECT * FROM expense_definitions WHERE id = ?`, [r.insertId]);
    res.status(201).json(created);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
