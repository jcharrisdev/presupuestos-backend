/**
 * routes/movimientos.js — MÓDULO: MOVIMIENTOS
 * Los movimientos son las transacciones reales dentro de un período.
 * La pantalla de detalle del presupuesto trabaja exclusivamente con movimientos.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { getPeriodoActivo, crearNuevoPeriodo } = require('../lib/periodo_helpers');

/**
 * GET /presupuestos/:id/detalle?firebase_uid=
 * Endpoint principal de la pantalla de detalle del presupuesto.
 * Devuelve:
 *   - periodo: el período activo (o crea uno si no existe)
 *   - movimientos: todas las transacciones del período activo
 *   - resumen: totales por tipo + porcentaje de pagados
 */
router.get('/presupuestos/:id/detalle', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[presupuesto]] = await db.execute(
      `SELECT id, nombre, monto_total FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const periodo = await getPeriodoActivo(id, firebase_uid);

    const [movimientos] = await db.execute(
      `SELECT * FROM movimientos
       WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ?
       ORDER BY id DESC`,
      [id, periodo.id, firebase_uid]
    );

    // Totales por tipo — fijos = compromisos, variables = gastos del período, ahorro = metas
    let totalFijos = 0, totalVariables = 0, totalAhorro = 0;
    let fijosPagados = 0, variablesPagados = 0;
    movimientos.forEach(m => {
      const esF = m.tipo === 'fijo' || m.tipo === 'fijo_x_periodo';
      const esV = m.tipo === 'no fijo' || m.tipo === 'variable';
      const esA = m.tipo === 'ahorro';
      if (esF) { totalFijos     += Number(m.monto); if (m.pagado) fijosPagados     += Number(m.monto_pagado_real || m.monto); }
      if (esV) { totalVariables += Number(m.monto); if (m.pagado) variablesPagados += Number(m.monto_pagado_real || m.monto); }
      if (esA) { totalAhorro    += Number(m.monto); }
    });

    // Gustitos (módulo independiente de micro-gastos)
    let totalGustitos = 0;
    try {
      const [[gustitosRow]] = await db.execute(
        `SELECT COALESCE(SUM(amount), 0) AS totalGustitos
         FROM gustitos WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL`,
        [id, firebase_uid]
      );
      totalGustitos = Math.round(Number(gustitosRow.totalGustitos) * 100) / 100;
    } catch (_) { /* tabla gustitos puede no existir */ }

    const pagados       = movimientos.filter(m => m.pagado === 1).length;
    const totalGastado  = totalFijos + totalVariables + totalAhorro;
    const montoTotal    = Number(presupuesto.monto_total);
    const comprometido  = parseFloat((totalFijos + totalAhorro).toFixed(2));          // gastos fijos del período
    const gastadoLibre  = parseFloat((totalVariables + totalGustitos).toFixed(2));    // gastos variables reales
    const disponible    = parseFloat((montoTotal - comprometido - gastadoLibre).toFixed(2));
    const porcentajeUtilizado = montoTotal > 0
      ? parseFloat(((totalGastado + totalGustitos) / montoTotal * 100).toFixed(1)) : 0;

    res.json({
      periodo,
      movimientos,
      presupuesto: { monto_total: montoTotal, nombre: presupuesto.nombre },
      resumen: {
        // Compromisos fijos del período (gastos del perfil trasladados al presupuesto)
        total_fijos:            parseFloat(totalFijos.toFixed(2)),
        total_fijos_pagados:    parseFloat(fijosPagados.toFixed(2)),
        // Gastos variables que el usuario fue añadiendo
        total_variables:        parseFloat(totalVariables.toFixed(2)),
        total_variables_pagados: parseFloat(variablesPagados.toFixed(2)),
        // Ahorros del período
        total_ahorro:           parseFloat(totalAhorro.toFixed(2)),
        // Micro-gastos (gustitos)
        total_gustitos:         totalGustitos,
        // Resumen ejecutivo
        comprometido,
        gastado_libre:          gastadoLibre,
        total_gastado:          parseFloat((comprometido + gastadoLibre).toFixed(2)),
        disponible_real:        disponible,
        porcentaje_utilizado:   porcentajeUtilizado,
        porcentaje_pagados:     movimientos.length > 0
          ? parseFloat((pagados / movimientos.length * 100).toFixed(1)) : 0,
        presupuesto_sano:       disponible >= 0,
      },
    });
  } catch (error) {
    console.error('Error detalle:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /presupuestos/:id/historico?firebase_uid=
 * Resumen de los últimos 6 períodos del presupuesto para la tab Historial.
 * Retorna totales por tipo de gasto y avance de pagos por período.
 */
router.get('/presupuestos/:id/historico', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[presupuesto]] = await db.execute(
      `SELECT id, nombre, monto_total FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const [periodos] = await db.execute(
      `SELECT
         p.id, p.numero_periodo, p.fecha_inicio, p.fecha_fin, p.estado,
         COALESCE(SUM(CASE WHEN m.tipo='fijo' OR m.tipo='fijo_x_periodo' THEN m.monto_pagado_real ELSE 0 END), 0) AS total_fijo,
         COALESCE(SUM(CASE WHEN m.tipo='no fijo' THEN m.monto_pagado_real ELSE 0 END), 0) AS total_no_fijo,
         COALESCE(SUM(CASE WHEN m.tipo='ahorro' THEN m.monto_pagado_real ELSE 0 END), 0) AS total_ahorro,
         COALESCE(SUM(m.monto_pagado_real), 0) AS total_gastado,
         COUNT(CASE WHEN m.pagado=1 THEN 1 END) AS movimientos_pagados,
         COUNT(m.id) AS movimientos_total
       FROM periodos p
       LEFT JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
       WHERE p.presupuesto_id = ? AND p.firebase_uid = ?
       GROUP BY p.id
       ORDER BY p.numero_periodo DESC
       LIMIT 6`,
      [id, firebase_uid]
    );
    res.json({ monto_total: presupuesto.monto_total, periodos });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /periodos/:id/resumen-cierre?firebase_uid=
// Devuelve el resumen completo del período antes de cerrarlo.
// El Flutter lo muestra como pantalla de confirmación: "Así te fue este período".
router.get('/periodos/:id/resumen-cierre', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[periodo]] = await db.execute(
      `SELECT p.*, pr.nombre AS presupuesto_nombre, pr.monto_total, pr.tipo_periodo
       FROM periodos p
       JOIN presupuestos pr ON pr.id = p.presupuesto_id
       WHERE p.id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!periodo) return res.status(404).json({ error: 'Período no encontrado' });

    const [movimientos] = await db.execute(
      `SELECT * FROM movimientos WHERE periodo_id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );

    let fijosPagado = 0, fijosTotal = 0;
    let variablesPagado = 0, variablesTotal = 0;
    let ahorroPagado = 0, ahorroTotal = 0;
    const sinPagar = [];

    for (const m of movimientos) {
      const esF = m.tipo === 'fijo' || m.tipo === 'fijo_x_periodo';
      const esV = m.tipo === 'no fijo' || m.tipo === 'variable';
      const esA = m.tipo === 'ahorro';
      const monto     = Number(m.monto);
      const montoPag  = Number(m.monto_pagado_real || 0);

      if (esF) { fijosTotal += monto; if (m.pagado) fijosPagado += montoPag; else sinPagar.push({ descripcion: m.descripcion, monto, tipo: 'fijo' }); }
      if (esV) { variablesTotal += monto; if (m.pagado) variablesPagado += montoPag; }
      if (esA) { ahorroTotal += monto; if (m.pagado) ahorroPagado += montoPag; }
    }

    const montoTotal    = Number(periodo.monto_total);
    const totalGastado  = fijosPagado + variablesPagado + ahorroPagado;
    const sobrante      = parseFloat((montoTotal - totalGastado).toFixed(2));

    // Gastos fijos del perfil que se incluirán en el siguiente período
    const [gastosFijosActivos] = await db.execute(
      `SELECT id, descripcion, monto_mensual, clasificacion FROM user_gastos_fijos
       WHERE firebase_uid = ? AND activo = 1 ORDER BY monto_mensual DESC`,
      [firebase_uid]
    );

    res.json({
      periodo: {
        id: periodo.id,
        numero:        periodo.numero_periodo,
        fecha_inicio:  periodo.fecha_inicio,
        fecha_fin:     periodo.fecha_fin,
        tipo_periodo:  periodo.tipo_periodo,
        presupuesto:   periodo.presupuesto_nombre,
      },
      balance: {
        ingreso_periodo:     montoTotal,
        total_fijos:         parseFloat(fijosTotal.toFixed(2)),
        total_fijos_pagado:  parseFloat(fijosPagado.toFixed(2)),
        total_variables:     parseFloat(variablesTotal.toFixed(2)),
        total_variables_pagado: parseFloat(variablesPagado.toFixed(2)),
        total_ahorro:        parseFloat(ahorroTotal.toFixed(2)),
        total_ahorro_pagado: parseFloat(ahorroPagado.toFixed(2)),
        total_gastado:       parseFloat(totalGastado.toFixed(2)),
        sobrante,
        cerro_positivo:      sobrante >= 0,
      },
      pagos_pendientes: sinPagar,
      siguiente_periodo: {
        gastos_fijos_base: gastosFijosActivos,
        total_fijos_base:  parseFloat(gastosFijosActivos.reduce((s, g) => s + Number(g.monto_mensual), 0).toFixed(2)),
        mensaje: '¿Deseas continuar con los mismos compromisos para el siguiente período?',
      },
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /periodos/:id/cerrar
// Cierra manualmente el período activo y abre el siguiente.
// El body permite modificar la configuración para el próximo período.
//
// Opciones en body:
//   continuar_igual: true   → cierra y abre el siguiente sin cambios
//   modificaciones: [       → lista de cambios a aplicar antes de abrir el siguiente
//     { tipo: 'eliminar_gasto_fijo', gasto_fijo_id: X },
//     { tipo: 'agregar_gasto_fijo',  descripcion, monto_mensual, tipo? },
//     { tipo: 'editar_gasto_fijo',   gasto_fijo_id, monto_mensual },
//   ]
router.post('/periodos/:id/cerrar', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, continuar_igual = true, modificaciones = [] } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[periodo]] = await db.execute(
      `SELECT p.*, pr.tipo_periodo FROM periodos p
       JOIN presupuestos pr ON pr.id = p.presupuesto_id
       WHERE p.id = ? AND p.firebase_uid = ? AND p.estado = 'activo'`,
      [id, firebase_uid]
    );
    if (!periodo) return res.status(404).json({ error: 'Período activo no encontrado' });

    // Cerrar el período actual
    await db.execute(
      `UPDATE periodos SET estado = 'cerrado', closed_at = NOW() WHERE id = ?`, [id]
    );

    // Aplicar modificaciones al perfil antes de abrir el siguiente período
    for (const mod of modificaciones) {
      if (mod.tipo === 'eliminar_gasto_fijo' && mod.gasto_fijo_id) {
        await db.execute(
          `UPDATE user_gastos_fijos SET activo = 0 WHERE id = ? AND firebase_uid = ?`,
          [mod.gasto_fijo_id, firebase_uid]
        );
      } else if (mod.tipo === 'agregar_gasto_fijo' && mod.descripcion && mod.monto_mensual) {
        await db.execute(
          `INSERT INTO user_gastos_fijos (firebase_uid, descripcion, monto_mensual, tipo, clasificacion, activo)
           VALUES (?, ?, ?, ?, 'importante', 1)`,
          [firebase_uid, mod.descripcion, mod.monto_mensual, mod.tipo || 'otro']
        );
      } else if (mod.tipo === 'editar_gasto_fijo' && mod.gasto_fijo_id && mod.monto_mensual) {
        await db.execute(
          `UPDATE user_gastos_fijos SET monto_mensual = ? WHERE id = ? AND firebase_uid = ?`,
          [mod.monto_mensual, mod.gasto_fijo_id, firebase_uid]
        );
      }
    }

    // Abrir el siguiente período
    const siguientePeriodo = await crearNuevoPeriodo(
      periodo.presupuesto_id, firebase_uid, periodo.tipo_periodo, periodo.fecha_fin
    );

    res.json({
      mensaje:           'Período cerrado correctamente',
      periodo_cerrado:   { id: Number(id), numero: periodo.numero_periodo },
      siguiente_periodo: siguientePeriodo,
      modificaciones_aplicadas: modificaciones.length,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

/**
 * POST /presupuestos/:id/movimientos
 * Crea movimientos manualmente desde una selección de gastos.
 * Para gastos 'no fijo': permite múltiples movimientos por período
 *   (ej: varias compras en el supermercado en el mismo mes).
 * Para gastos 'fijo' / 'ahorro': evita duplicados (ya se crean automáticamente).
 */
router.post('/presupuestos/:id/movimientos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, items } = req.body; // items: [{gasto_id, monto, subcategoria?}]

  if (!firebase_uid || !Array.isArray(items) || items.length === 0)
    return res.status(400).json({ error: 'Datos incompletos' });

  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);

    for (const item of items) {
      const { gasto_id, monto, subcategoria } = item;
      if (!gasto_id || monto == null || monto <= 0) continue;

      // Verificamos que el gasto existe y pertenece al usuario
      const [[gasto]] = await db.execute(
        `SELECT * FROM gastos WHERE id = ? AND presupuesto_id = ? AND firebase_uid = ?`,
        [gasto_id, id, firebase_uid]
      );
      if (!gasto) continue;

      // Para gastos no-fijo: permitimos múltiples movimientos en el mismo período
      // Para fijo/ahorro: saltamos si ya existe para no duplicar
      if (gasto.tipo !== 'no fijo') {
        const [[existing]] = await db.execute(
          `SELECT id FROM movimientos WHERE gasto_id = ? AND periodo_id = ? AND firebase_uid = ?`,
          [gasto_id, periodo.id, firebase_uid]
        );
        if (existing) continue; // Ya existe, no duplicar
      }

      // subcategoria: usa la del item si viene, si no hereda la del gasto
      const subcategoriaFinal = subcategoria || gasto.subcategoria || null;

      await db.execute(
        `INSERT INTO movimientos
         (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, subcategoria, created_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, NOW())`,
        [id, periodo.id, gasto.id, gasto.descripcion, monto, gasto.tipo, firebase_uid, subcategoriaFinal]
      );
    }

    res.status(201).json({ message: 'Movimientos creados correctamente', periodo_id: periodo.id });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /presupuestos/:id/gastos-seleccionables?firebase_uid=
 * Devuelve todos los gastos del presupuesto para el modal de "Agregar".
 * Incluye gastos de todos los tipos (no solo 'no fijo').
 * El Flutter decide cómo manejar duplicados según el tipo del gasto.
 */
router.get('/presupuestos/:id/gastos-seleccionables', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    const [gastos] = await db.execute(
      `SELECT g.* FROM gastos g
       WHERE g.presupuesto_id = ? AND g.firebase_uid = ? AND g.tipo = 'no fijo'
       AND NOT EXISTS (
         SELECT 1 FROM movimientos m
         WHERE m.gasto_id = g.id AND m.periodo_id = ?
       )
       ORDER BY g.descripcion`,
      [id, firebase_uid, periodo.id]
    );
    res.json({ periodo_id: periodo.id, gastos });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * PUT /movimientos/:id/pagar
 * Marca un movimiento como pagado con su monto real.
 * monto_pagado_real puede diferir del monto presupuestado.
 * Esta diferencia es visible en la pantalla de detalle para análisis financiero.
 */
router.put('/movimientos/:id/pagar', async (req, res) => {
  const { id } = req.params;
  const { pagado, monto_pagado_real, firebase_uid } = req.body;

  if (pagado === undefined || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  if (pagado === 1 && (!monto_pagado_real || monto_pagado_real <= 0))
    return res.status(400).json({ error: 'Monto pagado real inválido' });

  try {
    const [[movimiento]] = await db.execute(`SELECT id FROM movimientos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!movimiento) return res.status(404).json({ error: 'Movimiento no encontrado' });

    await db.execute(
      `UPDATE movimientos
       SET pagado = ?,
           monto_pagado_real = ?,
           pagado_por_uid = ?,
           fecha_pagado = CASE WHEN ? = 1 THEN NOW() ELSE NULL END
       WHERE id = ? AND firebase_uid = ?`,
      [pagado, pagado ? monto_pagado_real : null,
       pagado ? firebase_uid : null, pagado, id, firebase_uid]
    );
    res.json({ message: 'Movimiento actualizado correctamente' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
