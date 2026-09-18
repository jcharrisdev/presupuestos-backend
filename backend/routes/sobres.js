/**
 * routes/sobres.js — MÓDULO: SOBRES (categorías de gasto variable por presupuesto)
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');

// GET /presupuestos/:id/categorias
router.get('/presupuestos/:id/categorias', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [cats] = await db.execute(
      `SELECT * FROM presupuesto_categorias
       WHERE presupuesto_id = ? AND firebase_uid = ? AND activa = 1
       ORDER BY orden ASC, id ASC`,
      [presupuestoId, firebase_uid]
    );
    res.json({ categorias: cats });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /presupuestos/:id/categorias
router.post('/presupuestos/:id/categorias', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid, nombre, icono = 'category', color = '#6B7280', monto_asignado = 0, orden = 0 } = req.body;
  if (!firebase_uid || !nombre) return res.status(400).json({ error: 'firebase_uid y nombre son requeridos' });
  try {
    const [r] = await db.execute(
      `INSERT INTO presupuesto_categorias (presupuesto_id, firebase_uid, nombre, icono, color, monto_asignado, orden)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [presupuestoId, firebase_uid, nombre, icono, color, monto_asignado, orden]
    );
    const [[cat]] = await db.execute(`SELECT * FROM presupuesto_categorias WHERE id = ?`, [r.insertId]);
    res.status(201).json(cat);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /presupuestos/:id/categorias/:catId
router.put('/presupuestos/:id/categorias/:catId', async (req, res) => {
  const { catId } = req.params;
  const { firebase_uid, nombre, icono, color, monto_asignado, orden } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const fields = [], vals = [];
    if (nombre !== undefined)         { fields.push('nombre = ?');         vals.push(nombre); }
    if (icono !== undefined)          { fields.push('icono = ?');          vals.push(icono); }
    if (color !== undefined)          { fields.push('color = ?');          vals.push(color); }
    if (monto_asignado !== undefined) { fields.push('monto_asignado = ?'); vals.push(monto_asignado); }
    if (orden !== undefined)          { fields.push('orden = ?');          vals.push(orden); }
    if (!fields.length) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(catId, firebase_uid);
    const [result] = await db.execute(
      `UPDATE presupuesto_categorias SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Categoría no encontrada' });
    const [[cat]] = await db.execute(`SELECT * FROM presupuesto_categorias WHERE id = ?`, [catId]);
    res.json(cat);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /presupuestos/:id/categorias/:catId
router.delete('/presupuestos/:id/categorias/:catId', async (req, res) => {
  const { catId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(
      `UPDATE presupuesto_categorias SET activa = 0 WHERE id = ? AND firebase_uid = ?`,
      [catId, firebase_uid]
    );
    res.json({ message: 'Categoría eliminada' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /presupuestos/:id/gastos-rapidos — registrar gasto en sobre
router.post('/presupuestos/:id/gastos-rapidos', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid, categoria_id = null, descripcion = '', monto, fecha, es_hormiga = 0, periodo_id = null } = req.body;
  if (!firebase_uid || monto == null) return res.status(400).json({ error: 'firebase_uid y monto son requeridos' });
  try {
    const fechaFinal = fecha || new Date().toISOString().slice(0, 10);
    const [r] = await db.execute(
      `INSERT INTO presupuesto_gastos (presupuesto_id, periodo_id, categoria_id, firebase_uid, descripcion, monto, fecha, es_hormiga)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [presupuestoId, periodo_id, categoria_id, firebase_uid, descripcion, monto, fechaFinal, es_hormiga]
    );
    const [[gasto]] = await db.execute(`SELECT * FROM presupuesto_gastos WHERE id = ?`, [r.insertId]);
    res.status(201).json(gasto);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /presupuestos/:id/gastos-rapidos/:gastoId
router.delete('/presupuestos/:id/gastos-rapidos/:gastoId', async (req, res) => {
  const { gastoId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [result] = await db.execute(
      `DELETE FROM presupuesto_gastos WHERE id = ? AND firebase_uid = ?`, [gastoId, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ message: 'Eliminado' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /presupuestos/:id/resumen-sobres?periodo_id=X — resumen por categoría
router.get('/presupuestos/:id/resumen-sobres', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid, periodo_id } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [cats] = await db.execute(
      `SELECT * FROM presupuesto_categorias
       WHERE presupuesto_id = ? AND firebase_uid = ? AND activa = 1
       ORDER BY orden ASC, id ASC`,
      [presupuestoId, firebase_uid]
    );

    const periodoFilter = periodo_id ? 'AND pg.periodo_id = ?' : '';
    const periodoParams = periodo_id ? [presupuestoId, firebase_uid, periodo_id] : [presupuestoId, firebase_uid];
    const [gastos] = await db.execute(
      `SELECT pg.categoria_id, COALESCE(SUM(pg.monto), 0) AS gastado
       FROM presupuesto_gastos pg
       WHERE pg.presupuesto_id = ? AND pg.firebase_uid = ? ${periodoFilter}
       GROUP BY pg.categoria_id`,
      periodoParams
    );

    const gastoMap = {};
    gastos.forEach(g => { gastoMap[g.categoria_id ?? 'sin_categoria'] = Number(g.gastado); });

    const totalAsignado = cats.reduce((s, c) => s + Number(c.monto_asignado), 0);
    const totalGastado  = Object.values(gastoMap).reduce((s, v) => s + v, 0);

    const categoriasConGasto = cats.map(c => {
      const gastado = gastoMap[c.id] || 0;
      return {
        ...c,
        monto_asignado: Number(c.monto_asignado),
        monto_gastado: gastado,
        restante: Number(c.monto_asignado) - gastado,
        porcentaje: c.monto_asignado > 0 ? Math.round((gastado / Number(c.monto_asignado)) * 100) : 0,
      };
    });

    // Gastos sin categoría asignada
    const sinCategoria = gastoMap['sin_categoria'] || 0;

    res.json({
      total_asignado: parseFloat(totalAsignado.toFixed(2)),
      total_gastado:  parseFloat(totalGastado.toFixed(2)),
      sin_asignar:    parseFloat((totalAsignado - totalGastado).toFixed(2)),
      gastos_sin_categoria: parseFloat(sinCategoria.toFixed(2)),
      categorias: categoriasConGasto,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /presupuestos/:id/gastos-rapidos?periodo_id=X — lista de gastos del período
router.get('/presupuestos/:id/gastos-rapidos', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid, periodo_id } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const periodoFilter = periodo_id ? 'AND pg.periodo_id = ?' : '';
    const params = periodo_id ? [presupuestoId, firebase_uid, periodo_id] : [presupuestoId, firebase_uid];
    const [gastos] = await db.execute(
      `SELECT pg.*, pc.nombre AS categoria_nombre, pc.icono AS categoria_icono, pc.color AS categoria_color
       FROM presupuesto_gastos pg
       LEFT JOIN presupuesto_categorias pc ON pc.id = pg.categoria_id
       WHERE pg.presupuesto_id = ? AND pg.firebase_uid = ? ${periodoFilter}
       ORDER BY pg.fecha DESC, pg.id DESC`,
      params
    );
    const total = gastos.reduce((s, g) => s + Number(g.monto), 0);
    res.json({ gastos, total: parseFloat(total.toFixed(2)) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
