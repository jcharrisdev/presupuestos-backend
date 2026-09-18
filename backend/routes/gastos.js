/**
 * routes/gastos.js — MÓDULO: GASTOS
 * Los gastos son plantillas que definen qué se gasta en cada período.
 * No son transacciones directas; generan movimientos automáticamente.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { generarEventosCalendario } = require('../lib/calendario_helpers');
const { getPeriodoActivo } = require('../lib/periodo_helpers');

/**
 * POST /gastos/ahorroMeta
 * Crea un gasto de tipo 'ahorro' con cuota distribuida por período.
 * Calcula automáticamente la cuota según el tipo de período del presupuesto:
 *   - Mensual:   cuota = monto_total / tiempo_meses
 *   - Quincenal: cuota = monto_total / (tiempo_meses × 2)  ← 2 períodos por mes
 *
 * numero_quincena = cantidad total de períodos de pago (contador regresivo).
 */
router.post('/gastos/ahorroMeta', async (req, res) => {
  const { presupuesto_id, descripcion, monto, fecha, firebase_uid, tiempo_meses = 12 } = req.body;
  if (!presupuesto_id || !descripcion || monto == null || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });

  const fechaStr = fecha ? fecha.split('T')[0] : new Date().toISOString().split('T')[0];

  try {
    // Necesitamos el tipo_periodo para saber cuántos períodos caben en los meses indicados
    const [[presupuesto]] = await db.execute(
      `SELECT tipo_periodo FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [presupuesto_id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    // Calculamos cuántos períodos en total tiene el plan de ahorro
    const periodos_total = presupuesto.tipo_periodo === 'quincenal'
      ? Number(tiempo_meses) * 2   // Quincenal: 2 períodos por mes
      : Number(tiempo_meses);       // Mensual: 1 período por mes

    // Cuota por período (redondeando hacia arriba para no perder centavos)
    const monto_periodo = Math.ceil((monto / periodos_total) * 100) / 100;

    // Guardamos el gasto con el monto de la CUOTA (no el total)
    // numero_quincena actúa como contador regresivo de períodos restantes
    const [result] = await db.execute(
      `INSERT INTO gastos (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid, numero_quincena)
       VALUES (?, ?, ?, 'ahorro', ?, 0, ?, ?)`,
      [presupuesto_id, descripcion, monto_periodo, fechaStr, firebase_uid, periodos_total]
    );
    const gastoId = result.insertId;

    // Crear el movimiento para el período actual inmediatamente
    try {
      const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);
      await db.execute(
        `INSERT INTO movimientos
         (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
         VALUES (?, ?, ?, ?, ?, 'ahorro', 0, ?, NOW())`,
        [presupuesto_id, periodo.id, gastoId, descripcion, monto_periodo, firebase_uid]
      );
      // Decrementamos porque el primer período ya fue consumido
      await db.execute(
        `UPDATE gastos SET numero_quincena = numero_quincena - 1 WHERE id = ? AND numero_quincena > 0`,
        [gastoId]
      );
    } catch (err) { console.error('⚠️ No se pudo auto-crear movimiento para ahorro:', err.message); }

    res.status(201).json({ id: gastoId, monto_periodo, periodos_total, tipo_periodo: presupuesto.tipo_periodo, message: 'Ahorro/Meta creado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al crear ahorro/meta' });
  }
});

/**
 * POST /gastos
 * Crea un gasto estándar (fijo, no fijo, fijo_x_periodo).
 * Para tipos 'fijo', 'fijo_x_periodo' y 'ahorro': auto-crea movimiento en período activo.
 * Si tipo_fecha='fija': genera eventos en el calendario para los próximos 12 meses.
 */
router.post('/gastos', async (req, res) => {
  const {
    presupuesto_id, descripcion, monto, tipo, fecha, firebase_uid,
    tipo_fecha = 'flexible',
    dia_pago = null,
    frecuencia_pago = null,
    fecha_pago_exacta = null,
    genera_notificacion = false,
    dias_anticipacion = 3,
    subcategoria = null,
    clasificacion = null,
    gasto_global_id = null,      // Si viene de gastos_globales, enlaza aquí
    guardar_como_global = false, // Si true, auto-guarda en gastos_globales para reuso
  } = req.body;

  if (!presupuesto_id || !descripcion || monto == null || !tipo || !fecha || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });

  const clasificacionValida = ['esencial', 'importante', 'flexible'];
  const clasificacionFinal = clasificacionValida.includes(clasificacion) ? clasificacion : null;
  const fechaStr     = fecha.split('T')[0];
  const fechaPagoStr = fecha_pago_exacta ? fecha_pago_exacta.split('T')[0] : null;

  try {
    // Si viene de gastos_globales, copiar datos de ahí (descripcion/monto del global tienen prioridad)
    let globalId = gasto_global_id ? Number(gasto_global_id) : null;
    if (globalId) {
      const [[global]] = await db.execute(
        `SELECT * FROM gastos_globales WHERE id = ? AND firebase_uid = ?`, [globalId, firebase_uid]
      );
      if (!global) return res.status(404).json({ error: 'Gasto global no encontrado' });
    }

    const [result] = await db.execute(
      `INSERT INTO gastos
         (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid,
          tipo_fecha, dia_pago, frecuencia_pago, fecha_pago_exacta,
          genera_notificacion, dias_anticipacion, subcategoria, clasificacion, gasto_global_id)
       VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [presupuesto_id, descripcion, monto, tipo, fechaStr, firebase_uid,
       tipo_fecha, dia_pago, frecuencia_pago, fechaPagoStr,
       genera_notificacion ? 1 : 0, dias_anticipacion, subcategoria || null, clasificacionFinal, globalId]
    );
    const gastoId = result.insertId;

    // Auto-guardar en gastos_globales si es variable nuevo y el usuario lo indica
    if (guardar_como_global && !globalId) {
      const [gr] = await db.execute(
        `INSERT INTO gastos_globales (firebase_uid, nombre, monto, tipo, modalidad, frecuencia, dia_pago)
         VALUES (?, ?, ?, 'variable', 'individual', ?, ?)`,
        [firebase_uid, descripcion, monto, frecuencia_pago || 'unico', dia_pago]
      );
      await db.execute(`UPDATE gastos SET gasto_global_id = ? WHERE id = ?`, [gr.insertId, gastoId]);
      globalId = gr.insertId;
    }

    // Auto-crear movimiento para gastos fijos/periódicos
    if (tipo === 'fijo' || tipo === 'fijo_x_periodo' || tipo === 'ahorro') {
      try {
        const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);
        await db.execute(
          `INSERT INTO movimientos
             (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, subcategoria, clasificacion, created_at)
           VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, NOW())`,
          [presupuesto_id, periodo.id, gastoId, descripcion, monto, tipo, firebase_uid, subcategoria || null, clasificacionFinal]
        );
      } catch (err) { console.error('⚠️ No se pudo auto-crear movimiento:', err.message); }
    }

    // Si tiene fecha fija, generar eventos de calendario
    if (tipo_fecha === 'fija') {
      await generarEventosCalendario(gastoId, firebase_uid);
    }

    const [[created]] = await db.execute(`SELECT * FROM gastos WHERE id = ?`, [gastoId]);
    res.status(201).json(created);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al agregar gasto' });
  }
});

/**
 * GET /presupuestos/:id/gastos?firebase_uid=
 * Devuelve todos los gastos de un presupuesto.
 * También verifica/crea el período activo (efecto secundario intencional).
 */
router.get('/presupuestos/:id/gastos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    await getPeriodoActivo(id, firebase_uid); // Asegura que exista un período activo
    const [results] = await db.execute(
      `SELECT * FROM gastos WHERE presupuesto_id = ? AND firebase_uid = ? ORDER BY id DESC`,
      [id, firebase_uid]
    );
    res.json(results);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// PUT /gastos/:id — edición completa del gasto
// Permite cambiar descripción, monto, tipo_fecha, dia_pago, subcategoria, clasificacion.
// Si cambia tipo_fecha o dia_pago, regenera los eventos de calendario.
router.put('/gastos/:id', async (req, res) => {
  const { id } = req.params;
  const {
    firebase_uid, pagado, descripcion, monto, tipo, subcategoria, clasificacion,
    tipo_fecha, dia_pago, frecuencia_pago, fecha_pago_exacta, genera_notificacion, dias_anticipacion,
  } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[existing]] = await db.execute(
      `SELECT * FROM gastos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!existing) return res.status(404).json({ error: 'Gasto no encontrado' });

    const fields = [], vals = [];
    if (pagado !== undefined)              { fields.push('pagado = ?');              vals.push(pagado === true || pagado === 1 ? 1 : 0); }
    if (descripcion !== undefined)         { fields.push('descripcion = ?');         vals.push(descripcion); }
    if (monto !== undefined)               { fields.push('monto = ?');               vals.push(monto); }
    if (tipo !== undefined)                { fields.push('tipo = ?');                vals.push(tipo); }
    if (subcategoria !== undefined)        { fields.push('subcategoria = ?');        vals.push(subcategoria); }
    if (clasificacion !== undefined)       { fields.push('clasificacion = ?');       vals.push(clasificacion); }
    if (tipo_fecha !== undefined)          { fields.push('tipo_fecha = ?');          vals.push(tipo_fecha); }
    if (dia_pago !== undefined)            { fields.push('dia_pago = ?');            vals.push(dia_pago); }
    if (frecuencia_pago !== undefined)     { fields.push('frecuencia_pago = ?');     vals.push(frecuencia_pago); }
    if (fecha_pago_exacta !== undefined)   { fields.push('fecha_pago_exacta = ?');   vals.push(fecha_pago_exacta ? fecha_pago_exacta.split('T')[0] : null); }
    if (genera_notificacion !== undefined) { fields.push('genera_notificacion = ?'); vals.push(genera_notificacion ? 1 : 0); }
    if (dias_anticipacion !== undefined)   { fields.push('dias_anticipacion = ?');   vals.push(dias_anticipacion); }

    if (fields.length === 0) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(id, firebase_uid);
    await db.execute(`UPDATE gastos SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals);

    // Regenerar eventos de calendario si cambió tipo_fecha o dia_pago
    const nuevaTipoFecha   = tipo_fecha   ?? existing.tipo_fecha;
    const nuevoDiaPago     = dia_pago     ?? existing.dia_pago;
    const necesitaCalend   = tipo_fecha !== undefined || dia_pago !== undefined;
    if (necesitaCalend) {
      await db.execute(
        `DELETE FROM calendario_eventos WHERE gasto_id = ? AND estado = 'pendiente'`, [id]
      );
      if (nuevaTipoFecha === 'fija') {
        await generarEventosCalendario(id, firebase_uid);
      }
    }

    const [[updated]] = await db.execute(`SELECT * FROM gastos WHERE id = ?`, [id]);
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al actualizar gasto' });
  }
});

/**
 * PUT /presupuestos/:id/gastos/reanudar-fijos
 * Resetea el estado de pago de todos los movimientos FIJOS del período activo.
 * Se usa cuando el usuario quiere "limpiar" los pagos del período para
 * gestionar quién pagó qué en presupuestos compartidos.
 * IMPORTANTE: opera sobre movimientos (no sobre gastos) para no perder el historial.
 */
router.put('/presupuestos/:id/gastos/reanudar-fijos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    // Reseteamos pagado, monto_real y fecha_pago de los movimientos fijos del período
    const [result] = await db.execute(
      `UPDATE movimientos
       SET pagado = 0, monto_pagado_real = NULL, pagado_por_uid = NULL, fecha_pagado = NULL
       WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ? AND tipo IN ('fijo','fijo_x_periodo')`,
      [id, periodo.id, firebase_uid]
    );
    res.json({ message: 'Gastos fijos reanudados', afectados: result.affectedRows });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al reanudar gastos fijos' });
  }
});

/**
 * DELETE /gastos/:id?firebase_uid=
 * Elimina un gasto y sus movimientos asociados (CASCADE).
 * FIX: se agregó validación de firebase_uid para evitar que un usuario
 * elimine gastos de otro usuario si conoce el ID.
 */
router.delete('/gastos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [result] = await db.execute(
      `DELETE FROM gastos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    // Limpiar eventos de calendario pendientes asociados a este gasto
    await db.execute(
      `DELETE FROM calendario_eventos WHERE gasto_id = ? AND estado = 'pendiente'`, [id]
    );
    res.json({ message: 'Gasto eliminado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al eliminar gasto' });
  }
});

module.exports = router;
