/**
 * routes/ahorros.js — Metas de ahorro (gastos con tipo='ahorro') y sus aportaciones manuales.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');

/**
 * GET /ahorros?firebase_uid=
 * Lista las metas de ahorro del usuario con progreso calculado.
 */
router.get('/ahorros', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [ahorros] = await db.execute(
      `SELECT g.id, g.descripcion AS nombre,
              g.monto AS cuota_periodo,
              g.numero_quincena AS periodos_restantes,
              COALESCE(SUM(m.monto_pagado_real), 0) AS monto_ahorrado,
              COUNT(m.id) AS cuotas_pagadas,
              COALESCE((SELECT SUM(a.monto) FROM aportaciones_ahorro a WHERE a.gasto_id = g.id), 0) AS total_aportaciones,
              (SELECT COUNT(*) FROM movimientos m2 WHERE m2.gasto_id = g.id) AS cuotas_generadas
       FROM gastos g
       LEFT JOIN movimientos m ON m.gasto_id = g.id AND m.pagado = 1
       WHERE g.firebase_uid = ? AND g.tipo = 'ahorro'
       GROUP BY g.id`,
      [firebase_uid]
    );

    // monto_meta_total = cuota × (cuotas ya generadas + períodos restantes) = total original
    // Para ahorros sin límite (periodos_restantes IS NULL) usamos solo cuotas generadas como referencia
    const result = ahorros.map(a => {
      const totalAhorrado    = parseFloat(a.monto_ahorrado) + parseFloat(a.total_aportaciones);
      const completado       = a.periodos_restantes === 0;
      const cuotasGeneradas  = parseInt(a.cuotas_generadas) || 0;
      const periodosRestantes = a.periodos_restantes !== null ? parseInt(a.periodos_restantes) : null;
      const totalCuotas      = periodosRestantes !== null ? cuotasGeneradas + periodosRestantes : null;
      const metaTotal        = totalCuotas !== null && totalCuotas > 0
        ? parseFloat((parseFloat(a.cuota_periodo) * totalCuotas).toFixed(2))
        : null;
      return {
        ...a,
        monto_meta: a.cuota_periodo, // cuota por período (compatibilidad hacia atrás)
        monto_meta_total: metaTotal, // meta total real — usar este para barras de progreso
        total_ahorrado: parseFloat(totalAhorrado.toFixed(2)),
        completado,
      };
    });
    res.json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al obtener ahorros' });
  }
});

/**
 * POST /ahorros/:id/aportaciones
 * Registra una aportación manual a una meta de ahorro.
 */
router.post('/ahorros/:id/aportaciones', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, monto, nota, fecha } = req.body;
  if (!firebase_uid || !monto || !fecha) return res.status(400).json({ error: 'Datos incompletos' });
  if (Number(monto) <= 0) return res.status(400).json({ error: 'Monto debe ser mayor a 0' });
  try {
    const [[gasto]] = await db.execute(
      `SELECT id FROM gastos WHERE id = ? AND firebase_uid = ? AND tipo = 'ahorro'`,
      [id, firebase_uid]
    );
    if (!gasto) return res.status(404).json({ error: 'Meta de ahorro no encontrada' });
    const [result] = await db.execute(
      `INSERT INTO aportaciones_ahorro (gasto_id, firebase_uid, monto, nota, fecha) VALUES (?, ?, ?, ?, ?)`,
      [id, firebase_uid, monto, nota || null, fecha]
    );
    res.status(201).json({ id: result.insertId, gasto_id: Number(id), monto, nota, fecha });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /ahorros/:id/aportaciones?firebase_uid=
 * Lista las aportaciones manuales de una meta de ahorro.
 */
router.get('/ahorros/:id/aportaciones', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [aportaciones] = await db.execute(
      `SELECT * FROM aportaciones_ahorro WHERE gasto_id = ? AND firebase_uid = ? ORDER BY fecha DESC`,
      [id, firebase_uid]
    );
    const total = aportaciones.reduce((s, a) => s + Number(a.monto), 0);
    res.json({ aportaciones, total_aportado: total });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /aportaciones/:id?firebase_uid=
 * Elimina una aportación manual.
 */
router.delete('/aportaciones/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[ap]] = await db.execute(
      `SELECT a.id FROM aportaciones_ahorro a
       JOIN gastos g ON g.id = a.gasto_id
       WHERE a.id = ? AND a.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!ap) return res.status(404).json({ error: 'Aportación no encontrada' });
    await db.execute(`DELETE FROM aportaciones_ahorro WHERE id = ?`, [id]);
    res.json({ deleted: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /ahorros/:id?firebase_uid=
 * Elimina una meta de ahorro.
 */
router.delete('/ahorros/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [result] = await db.execute(
      `DELETE FROM gastos WHERE id = ? AND tipo = 'ahorro' AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Ahorro no encontrado' });
    res.json({ message: 'Ahorro eliminado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al eliminar ahorro' });
  }
});

module.exports = router;
