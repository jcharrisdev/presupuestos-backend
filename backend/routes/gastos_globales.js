/**
 * routes/gastos_globales.js — MÓDULO: GASTOS GLOBALES
 * Gastos reutilizables independientes de presupuesto.
 * Flag individual/compartido. Pueden usarse en cualquier presupuesto.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { generarEventosCalendario, generarEventosPerfilGasto: _generarEventosPerfilGasto } = require('../lib/calendario_helpers');

// GET /gastos-globales/stats?firebase_uid= — totales para widget del AppBar
router.get('/gastos-globales/stats', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[stats]] = await db.execute(
      `SELECT
         COUNT(*)                                        AS total,
         SUM(modalidad = 'individual')                  AS individuales,
         SUM(modalidad = 'compartido')                  AS compartidos,
         SUM(tipo = 'fijo')                             AS fijos,
         SUM(tipo = 'variable')                         AS variables,
         COALESCE(SUM(CASE WHEN frecuencia = 'mensual' THEN monto ELSE 0 END), 0) AS total_mensual_estimado
       FROM gastos_globales
       WHERE firebase_uid = ? AND activo = 1`,
      [firebase_uid]
    );
    // Cuántos gastos globales están en uso en presupuestos activos
    const [[enUso]] = await db.execute(
      `SELECT COUNT(DISTINCT g.gasto_global_id) AS en_uso
       FROM gastos g
       JOIN presupuestos p ON p.id = g.presupuesto_id
       WHERE g.firebase_uid = ? AND g.gasto_global_id IS NOT NULL`,
      [firebase_uid]
    );
    res.json({
      total:                    Number(stats.total),
      individuales:             Number(stats.individuales),
      compartidos:              Number(stats.compartidos),
      fijos:                    Number(stats.fijos),
      variables:                Number(stats.variables),
      total_mensual_estimado:   parseFloat(Number(stats.total_mensual_estimado).toFixed(2)),
      en_uso_en_presupuestos:   Number(enUso.en_uso),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /gastos-globales?firebase_uid=&modalidad=&tipo=&buscar=&activo=1
router.get('/gastos-globales', async (req, res) => {
  const { firebase_uid, modalidad, tipo, buscar, activo = '1' } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // veces_usado = cuántos gastos en presupuestos enlazan a este global
    let sql = `
      SELECT gg.*,
             COALESCE(uso.veces_usado, 0) AS veces_usado,
             uso.ultimo_presupuesto_id
      FROM gastos_globales gg
      LEFT JOIN (
        SELECT gasto_global_id,
               COUNT(*)  AS veces_usado,
               MAX(presupuesto_id) AS ultimo_presupuesto_id
        FROM gastos
        WHERE gasto_global_id IS NOT NULL
        GROUP BY gasto_global_id
      ) uso ON uso.gasto_global_id = gg.id
      WHERE gg.firebase_uid = ?`;
    const params = [firebase_uid];
    if (activo !== 'todos') { sql += ` AND gg.activo = ?`;    params.push(Number(activo)); }
    if (modalidad)          { sql += ` AND gg.modalidad = ?`; params.push(modalidad); }
    if (tipo)               { sql += ` AND gg.tipo = ?`;      params.push(tipo); }
    if (buscar)             { sql += ` AND gg.nombre LIKE ?`; params.push(`%${buscar}%`); }
    sql += ` ORDER BY uso.veces_usado DESC, gg.nombre ASC`;
    const [rows] = await db.execute(sql, params);
    const totalMensual = rows
      .filter(g => g.activo && g.frecuencia === 'mensual')
      .reduce((s, g) => s + Number(g.monto), 0);
    res.json({ gastos: rows, total_mensual: parseFloat(totalMensual.toFixed(2)) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /gastos-globales — crear gasto global
router.post('/gastos-globales', async (req, res) => {
  const {
    firebase_uid, nombre, descripcion, monto,
    categoria = 'otro', tipo = 'variable', modalidad = 'individual',
    frecuencia = 'mensual', dia_pago = null, notas = null,
  } = req.body;
  if (!firebase_uid || !nombre || monto == null)
    return res.status(400).json({ error: 'firebase_uid, nombre y monto son requeridos' });
  try {
    const [result] = await db.execute(
      `INSERT INTO gastos_globales
         (firebase_uid, nombre, descripcion, monto, categoria, tipo, modalidad, frecuencia, dia_pago, notas)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, descripcion || null, monto, categoria, tipo, modalidad, frecuencia, dia_pago, notas]
    );
    if (dia_pago) {
      await _generarEventosPerfilGasto(firebase_uid, null, nombre, monto, dia_pago);
    }
    const [[created]] = await db.execute(`SELECT * FROM gastos_globales WHERE id = ?`, [result.insertId]);
    res.status(201).json(created);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /gastos-globales/:id — editar gasto global (incluyendo cambio individual↔compartido)
router.put('/gastos-globales/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, nombre, descripcion, monto, categoria, tipo, modalidad, frecuencia, dia_pago, notas, activo } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[existing]] = await db.execute(
      `SELECT * FROM gastos_globales WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!existing) return res.status(404).json({ error: 'Gasto no encontrado' });

    const fields = [], vals = [];
    if (nombre !== undefined)      { fields.push('nombre = ?');      vals.push(nombre); }
    if (descripcion !== undefined) { fields.push('descripcion = ?'); vals.push(descripcion); }
    if (monto !== undefined)       { fields.push('monto = ?');       vals.push(monto); }
    if (categoria !== undefined)   { fields.push('categoria = ?');   vals.push(categoria); }
    if (tipo !== undefined)        { fields.push('tipo = ?');         vals.push(tipo); }
    if (modalidad !== undefined)   { fields.push('modalidad = ?');   vals.push(modalidad); }
    if (frecuencia !== undefined)  { fields.push('frecuencia = ?');  vals.push(frecuencia); }
    if (dia_pago !== undefined)    { fields.push('dia_pago = ?');    vals.push(dia_pago); }
    if (notas !== undefined)       { fields.push('notas = ?');       vals.push(notas); }
    if (activo !== undefined)      { fields.push('activo = ?');      vals.push(activo); }
    if (fields.length === 0) return res.status(400).json({ error: 'Nada que actualizar' });

    vals.push(id, firebase_uid);
    await db.execute(`UPDATE gastos_globales SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals);
    const [[updated]] = await db.execute(`SELECT * FROM gastos_globales WHERE id = ?`, [id]);
    res.json(updated);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /gastos-globales/:id/usar — agrega un gasto global al período activo de un presupuesto
// Cuerpo: { firebase_uid, presupuesto_id, fecha, tipo? }
// Copia nombre/monto/dia_pago/frecuencia del global. El tipo por defecto es 'no fijo' (variable).
router.post('/gastos-globales/:id/usar', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, presupuesto_id, fecha, tipo = 'no fijo', subcategoria, clasificacion } = req.body;
  if (!firebase_uid || !presupuesto_id || !fecha)
    return res.status(400).json({ error: 'firebase_uid, presupuesto_id y fecha son requeridos' });
  try {
    const [[global]] = await db.execute(
      `SELECT * FROM gastos_globales WHERE id = ? AND firebase_uid = ? AND activo = 1`,
      [id, firebase_uid]
    );
    if (!global) return res.status(404).json({ error: 'Gasto global no encontrado o inactivo' });

    const fechaStr   = fecha.split('T')[0];
    const tipofecha  = global.dia_pago ? 'fija' : 'flexible';
    const [result] = await db.execute(
      `INSERT INTO gastos
         (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid,
          tipo_fecha, dia_pago, frecuencia_pago, subcategoria, clasificacion, gasto_global_id)
       VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)`,
      [presupuesto_id, global.nombre, global.monto, tipo, fechaStr, firebase_uid,
       tipofecha, global.dia_pago, global.frecuencia,
       subcategoria || null, clasificacion || null, global.id]
    );
    const gastoId = result.insertId;

    // Generar eventos de calendario si tiene día de pago
    if (tipofecha === 'fija') {
      await generarEventosCalendario(gastoId, firebase_uid);
    }

    const [[creado]] = await db.execute(`SELECT * FROM gastos WHERE id = ?`, [gastoId]);
    res.status(201).json({ gasto: creado, gasto_global: global });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /gastos-globales/:id — soft delete
router.delete('/gastos-globales/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [result] = await db.execute(
      `UPDATE gastos_globales SET activo = 0 WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
