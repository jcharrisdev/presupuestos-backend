/**
 * routes/gastos_variables_base.js — MÓDULO: GASTOS VARIABLES BASE
 * Gastos esperados pero variables: supermercado, gasolina, medicinas, etc.
 * Son la segunda capa del perfil financiero (después de los compromisos fijos).
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { _logInfo } = require('../lib/logger');
const { _generarAplicaMeses } = require('../lib/calculos_financieros');
const { _recalcularEstimadosAnio } = require('../lib/mes_helpers');

const CATEGORIAS_VALIDAS = [
  'vivienda','alimentacion','transporte','deudas','salud','educacion',
  'ocio','familia','emergencias','deportes','ropa','tecnologia','otro',
];

// GET /user/gastos-variables-base?firebase_uid=
router.get('/user/gastos-variables-base', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT gvb.*, s.nombre AS subcategoria_nombre
       FROM gastos_variables_base gvb
       LEFT JOIN subcategorias s ON s.id = gvb.subcategoria_id
       WHERE gvb.firebase_uid = ? AND gvb.activo = 1
       ORDER BY gvb.categoria ASC, gvb.monto_estimado DESC`,
      [firebase_uid]
    );
    const totalMensual = rows.reduce((s, g) => {
      const factor = g.frecuencia === 'quincenal' ? 2
                   : g.frecuencia === 'semanal'   ? 4.33
                   : g.frecuencia === 'anual'      ? 1/12
                   : 1;
      return s + Number(g.monto_estimado) * factor;
    }, 0);
    // Agrupar por categoría
    const porCategoria = {};
    for (const g of rows) {
      if (!porCategoria[g.categoria]) porCategoria[g.categoria] = { categoria: g.categoria, items: [], subtotal: 0 };
      porCategoria[g.categoria].items.push(g);
      porCategoria[g.categoria].subtotal += Number(g.monto_estimado);
    }
    res.json({ gastos: rows, total_mensual: parseFloat(totalMensual.toFixed(2)), por_categoria: Object.values(porCategoria) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/gastos-variables-base
// mes_inicio (1-12): mes desde el cual aplica. Default 1 (enero)
// mes_fin    (1-12): mes hasta el cual aplica. Default 12 (diciembre)
router.post('/user/gastos-variables-base', async (req, res) => {
  const { firebase_uid, nombre, categoria = 'otro', categoria_custom,
    subcategoria_id, monto_estimado, frecuencia = 'mensual',
    mes_inicio = 1, mes_fin = 12, en_calendario = 0, notas } = req.body;
  if (!firebase_uid || !nombre || monto_estimado == null)
    return res.status(400).json({ error: 'firebase_uid, nombre y monto_estimado requeridos' });
  try {
    // Si la categoría es "otro" y hay una personalizada, crearla/buscarla primero
    let categoriaFinal = categoria;
    if (categoria === 'otro' && categoria_custom) {
      const nombreCat = categoria_custom.trim().toLowerCase();
      const [[existeCat]] = await db.execute(
        `SELECT id FROM subcategorias WHERE firebase_uid = ? AND categoria = 'custom' AND nombre = ?`,
        [firebase_uid, nombreCat]
      );
      if (!existeCat) {
        await db.execute(
          `INSERT INTO subcategorias (firebase_uid, categoria, nombre) VALUES (?, 'custom', ?)`,
          [firebase_uid, nombreCat]
        );
      }
      categoriaFinal = nombreCat;
    }
    const aplicaMeses = _generarAplicaMeses(mes_inicio, mes_fin);
    const [r] = await db.execute(
      `INSERT INTO gastos_variables_base
         (firebase_uid, nombre, categoria, subcategoria_id, monto_estimado, frecuencia,
          aplica_meses, mes_inicio, mes_fin, en_calendario, notas)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, categoriaFinal, subcategoria_id || null, monto_estimado, frecuencia,
       JSON.stringify(aplicaMeses), Number(mes_inicio), Number(mes_fin), en_calendario ? 1 : 0, notas || null]
    );
    const [[created]] = await db.execute(`SELECT * FROM gastos_variables_base WHERE id = ?`, [r.insertId]);
    res.status(201).json(created);
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _logInfo('/user/gastos-variables-base', `Variable base creada: "${nombre}" $${Number(monto_estimado).toFixed(2)} - meses ${mes_inicio}-${mes_fin}`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /user/gastos-variables-base/:id
router.put('/user/gastos-variables-base/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, nombre, categoria, categoria_custom, subcategoria_id,
    monto_estimado, frecuencia, mes_inicio, mes_fin, en_calendario, notas, activo } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const fields = [], vals = [];
    let categoriaFinal = categoria;
    if (categoria === 'otro' && categoria_custom) {
      categoriaFinal = categoria_custom.trim().toLowerCase();
      const [[existeCat]] = await db.execute(
        `SELECT id FROM subcategorias WHERE firebase_uid = ? AND categoria = 'custom' AND nombre = ?`,
        [firebase_uid, categoriaFinal]
      );
      if (!existeCat) {
        await db.execute(
          `INSERT INTO subcategorias (firebase_uid, categoria, nombre) VALUES (?, 'custom', ?)`,
          [firebase_uid, categoriaFinal]
        );
      }
    }
    if (nombre !== undefined)          { fields.push('nombre = ?');          vals.push(nombre); }
    if (categoriaFinal !== undefined)  { fields.push('categoria = ?');       vals.push(categoriaFinal); }
    if (subcategoria_id !== undefined) { fields.push('subcategoria_id = ?'); vals.push(subcategoria_id); }
    if (monto_estimado !== undefined)  { fields.push('monto_estimado = ?');  vals.push(monto_estimado); }
    if (frecuencia !== undefined)      { fields.push('frecuencia = ?');      vals.push(frecuencia); }
    if (en_calendario !== undefined)   { fields.push('en_calendario = ?');   vals.push(en_calendario ? 1 : 0); }
    if (notas !== undefined)           { fields.push('notas = ?');           vals.push(notas); }
    if (activo !== undefined)          { fields.push('activo = ?');          vals.push(activo); }
    // Recalcular aplica_meses si cambia el rango
    if (mes_inicio !== undefined || mes_fin !== undefined) {
      const [[existing]] = await db.execute(`SELECT mes_inicio, mes_fin FROM gastos_variables_base WHERE id = ?`, [id]);
      const nuevoInicio = mes_inicio ?? existing?.mes_inicio ?? 1;
      const nuevoFin    = mes_fin    ?? existing?.mes_fin    ?? 12;
      const nuevosM = _generarAplicaMeses(nuevoInicio, nuevoFin);
      fields.push('mes_inicio = ?', 'mes_fin = ?', 'aplica_meses = ?');
      vals.push(Number(nuevoInicio), Number(nuevoFin), JSON.stringify(nuevosM));
    }
    if (!fields.length) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(id, firebase_uid);
    const [r] = await db.execute(`UPDATE gastos_variables_base SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals);
    if (!r.affectedRows) return res.status(404).json({ error: 'No encontrado' });
    const [[updated]] = await db.execute(`SELECT * FROM gastos_variables_base WHERE id = ?`, [id]);
    res.json(updated);
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _logInfo(`/user/gastos-variables-base/${id}`, `Variable base editada: "${updated.nombre}" $${Number(updated.monto_estimado).toFixed(2)}`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /user/gastos-variables-base/:id
router.delete('/user/gastos-variables-base/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [r] = await db.execute(`UPDATE gastos_variables_base SET activo = 0 WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!r.affectedRows) return res.status(404).json({ error: 'No encontrado' });
    res.json({ success: true });
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _logInfo(`/user/gastos-variables-base/${id}`, `Variable base eliminada (id=${id})`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/gastos-variables-base/bulk
router.post('/user/gastos-variables-base/bulk', async (req, res) => {
  const { firebase_uid, variables } = req.body;
  if (!firebase_uid || !Array.isArray(variables))
    return res.status(400).json({ error: 'firebase_uid y variables[] requeridos' });
  try {
    const ids = [];
    for (const v of variables) {
      const [r] = await db.execute(
        `INSERT INTO gastos_variables_base (firebase_uid, nombre, categoria, monto_estimado, frecuencia, activo)
         VALUES (?, ?, ?, ?, 'mensual', 1)`,
        [firebase_uid, v.nombre, v.categoria, Number(v.monto_estimado)]
      );
      ids.push(r.insertId);
    }
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    res.status(201).json({ ids, count: ids.length });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
