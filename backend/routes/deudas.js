/**
 * routes/deudas.js — Deudas como entidad propia: CRUD, abonos, sincronización
 * de eventos de calendario, y estrategia de pago (avalanche/snowball) con
 * proyección y simulador.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { _logInfo } = require('../lib/logger');
const { _recalcularEstimadosAnio } = require('../lib/mes_helpers');
const { _simularDeudas } = require('../lib/calculos_financieros');

// Enriquece una deuda con campos calculados útiles para el frontend
function _enriquecerDeuda(d) {
  const cuotas_restantes = d.es_letra && d.num_cuotas_total
    ? Math.max(0, Number(d.num_cuotas_total) - Number(d.num_cuotas_pagadas || 0))
    : null;
  let fecha_fin_estimada = null;
  if (d.es_letra && cuotas_restantes !== null && d.fecha_proximo_pago) {
    const base = new Date(d.fecha_proximo_pago);
    base.setMonth(base.getMonth() + cuotas_restantes - 1);
    fecha_fin_estimada = base.toISOString().slice(0, 10);
  }
  return { ...d, cuotas_restantes, fecha_fin_estimada };
}

// POST /deudas/sync-calendario — sincroniza manualmente los eventos de calendario de todas las deudas
router.post('/deudas/sync-calendario', async (req, res) => {
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await _sincronizarEventosDeudas(firebase_uid);
    res.json({ ok: true, mensaje: 'Eventos de deudas sincronizados' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Genera/actualiza eventos de calendario para los pagos próximos de todas las deudas activas.
// Se llama como fire-and-forget tras crear o editar una deuda.
async function _sincronizarEventosDeudas(firebase_uid) {
  const [deudas] = await db.execute(
    `SELECT id, nombre, fecha_proximo_pago, IF(es_letra=1, cuota_fija, pago_minimo) AS cuota
     FROM deudas WHERE firebase_uid = ? AND activa = 1 AND fecha_proximo_pago IS NOT NULL`,
    [firebase_uid]);
  for (const d of deudas) {
    // Eliminar eventos pendientes/vencidos anteriores de esta deuda
    await db.execute(
      `DELETE FROM calendario_eventos WHERE firebase_uid = ? AND deuda_id = ? AND estado IN ('pendiente','vencido')`,
      [firebase_uid, d.id]).catch(() => {});
    // Crear evento para los próximos 3 meses de pago
    const base = new Date(d.fecha_proximo_pago);
    for (let i = 0; i < 3; i++) {
      const fecha = new Date(base);
      fecha.setMonth(fecha.getMonth() + i);
      const fechaStr = fecha.toISOString().slice(0, 10);
      const estado = fecha < new Date() ? 'vencido' : 'pendiente';
      await db.execute(
        `INSERT INTO calendario_eventos (firebase_uid, deuda_id, titulo, tipo, fecha_evento, monto_esperado, estado, notificacion_activa, dias_anticipacion)
         VALUES (?, ?, ?, 'pago', ?, ?, ?, 1, 3)`,
        [firebase_uid, d.id, d.nombre, fechaStr, Number(d.cuota || 0), estado]
      ).catch(() => {});
    }
  }
}

// GET /deudas?firebase_uid=   — lista deudas activas del usuario
router.get('/deudas', async (req, res) => {
  const { firebase_uid, incluir_saldadas } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const soloActivas = incluir_saldadas === '1' ? '' : "AND activa = 1";
    const [rows] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? ${soloActivas} ORDER BY fecha_proximo_pago ASC, created_at DESC`,
      [firebase_uid]
    );
    const enriquecidas = rows.map(_enriquecerDeuda);
    const totalPendiente  = enriquecidas.reduce((s, d) => s + Number(d.monto_pendiente), 0);
    const totalPagoMinimo = enriquecidas.reduce((s, d) => s + Number(d.pago_minimo || 0), 0);
    res.json({ deudas: enriquecidas, total_pendiente: totalPendiente, total_pago_minimo: totalPagoMinimo });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// POST /deudas — crear nueva deuda o letra (compra a plazo)
// Para letras: es_letra=1, cuota_fija=X, num_cuotas_total=N, nombre_acreedor=Y, fecha_inicio=YYYY-MM-DD
// tasa_interes=0 en letras sin interés. monto_pendiente = cuota_fija * (num_cuotas_total - num_cuotas_pagadas)
router.post('/deudas', async (req, res) => {
  const {
    firebase_uid, nombre, tipo = 'personal',
    monto_total, monto_pendiente,
    tasa_interes = null, pago_minimo = null,
    fecha_proximo_pago = null, notas = null,
    // Campos de letra/cuota
    es_letra = 0, num_cuotas_total = null, num_cuotas_pagadas = 0,
    cuota_fija = null, nombre_acreedor = null, fecha_inicio = null,
  } = req.body;
  if (!firebase_uid || !nombre || monto_total == null || monto_pendiente == null)
    return res.status(400).json({ error: 'firebase_uid, nombre, monto_total y monto_pendiente son requeridos' });
  try {
    const tiposValidos = ['tarjeta_credito','prestamo','hipoteca','auto','personal','letra','otro'];
    const tipoFinal = tiposValidos.includes(tipo) ? tipo : 'personal';
    // Para letras: pago_minimo = cuota_fija si no se especifica
    const pagoMinFinal = pago_minimo ?? (es_letra && cuota_fija ? cuota_fija : null);
    const [result] = await db.execute(
      `INSERT INTO deudas
         (firebase_uid, nombre, tipo, monto_total, monto_pendiente, tasa_interes,
          pago_minimo, fecha_proximo_pago, notas,
          es_letra, num_cuotas_total, num_cuotas_pagadas, cuota_fija, nombre_acreedor, fecha_inicio)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, tipoFinal, monto_total, monto_pendiente, tasa_interes,
       pagoMinFinal, fecha_proximo_pago, notas,
       Number(es_letra), num_cuotas_total, Number(num_cuotas_pagadas), cuota_fija, nombre_acreedor, fecha_inicio]
    );
    const [[created]] = await db.execute(`SELECT * FROM deudas WHERE id = ?`, [result.insertId]);
    res.status(201).json(_enriquecerDeuda(created));
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _sincronizarEventosDeudas(firebase_uid).catch(() => {});
    _logInfo('/deudas', `Deuda creada: "${nombre}" ${es_letra ? 'letra' : tipo} - pendiente $${Number(monto_pendiente).toFixed(2)}`, firebase_uid);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// PUT /deudas/:id — editar deuda o letra
router.put('/deudas/:id', async (req, res) => {
  const { id } = req.params;
  const {
    firebase_uid, nombre, tipo, monto_total, monto_pendiente,
    tasa_interes, pago_minimo, fecha_proximo_pago, notas,
    es_letra, num_cuotas_total, num_cuotas_pagadas, cuota_fija, nombre_acreedor, fecha_inicio,
  } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const fields = [], vals = [];
    if (nombre !== undefined)             { fields.push('nombre = ?');             vals.push(nombre); }
    if (tipo !== undefined)               { fields.push('tipo = ?');               vals.push(tipo); }
    if (monto_total !== undefined)        { fields.push('monto_total = ?');        vals.push(monto_total); }
    if (monto_pendiente !== undefined)    { fields.push('monto_pendiente = ?');    vals.push(monto_pendiente); }
    if (tasa_interes !== undefined)       { fields.push('tasa_interes = ?');       vals.push(tasa_interes); }
    if (pago_minimo !== undefined)        { fields.push('pago_minimo = ?');        vals.push(pago_minimo); }
    if (fecha_proximo_pago !== undefined) { fields.push('fecha_proximo_pago = ?'); vals.push(fecha_proximo_pago); }
    if (notas !== undefined)              { fields.push('notas = ?');              vals.push(notas); }
    if (es_letra !== undefined)           { fields.push('es_letra = ?');           vals.push(Number(es_letra)); }
    if (num_cuotas_total !== undefined)   { fields.push('num_cuotas_total = ?');   vals.push(num_cuotas_total); }
    if (num_cuotas_pagadas !== undefined) { fields.push('num_cuotas_pagadas = ?'); vals.push(num_cuotas_pagadas); }
    if (cuota_fija !== undefined)         { fields.push('cuota_fija = ?');         vals.push(cuota_fija); }
    if (nombre_acreedor !== undefined)    { fields.push('nombre_acreedor = ?');    vals.push(nombre_acreedor); }
    if (fecha_inicio !== undefined)       { fields.push('fecha_inicio = ?');       vals.push(fecha_inicio); }
    if (fields.length === 0) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(id, firebase_uid);
    const [result] = await db.execute(
      `UPDATE deudas SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Deuda no encontrada' });
    const [[updated]] = await db.execute(`SELECT * FROM deudas WHERE id = ?`, [id]);
    res.json(_enriquecerDeuda(updated));
    _sincronizarEventosDeudas(firebase_uid).catch(() => {});
    _logInfo(`/deudas/${id}`, `Deuda editada: "${updated.nombre}" - pendiente $${Number(updated.monto_pendiente).toFixed(2)}`, firebase_uid);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// PATCH /deudas/:id/abono — registrar un abono (reduce monto_pendiente)
router.patch('/deudas/:id/abono', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, monto_abono, fecha_proximo_pago } = req.body;
  if (!firebase_uid || monto_abono == null) return res.status(400).json({ error: 'firebase_uid y monto_abono son requeridos' });
  if (Number(monto_abono) <= 0) return res.status(400).json({ error: 'monto_abono debe ser mayor a 0' });
  try {
    const [[deuda]] = await db.execute(
      `SELECT * FROM deudas WHERE id = ? AND firebase_uid = ? AND activa = 1`, [id, firebase_uid]
    );
    if (!deuda) return res.status(404).json({ error: 'Deuda no encontrada o ya saldada' });
    const nuevoPendiente = Math.max(0, Number(deuda.monto_pendiente) - Number(monto_abono));
    const nuevaActiva = nuevoPendiente > 0 ? 1 : 0;
    const updateFields = ['monto_pendiente = ?', 'activa = ?'];
    const updateVals   = [nuevoPendiente, nuevaActiva];
    if (fecha_proximo_pago) { updateFields.push('fecha_proximo_pago = ?'); updateVals.push(fecha_proximo_pago); }
    updateVals.push(id, firebase_uid);
    await db.execute(`UPDATE deudas SET ${updateFields.join(', ')} WHERE id = ? AND firebase_uid = ?`, updateVals);
    const [[updated]] = await db.execute(`SELECT * FROM deudas WHERE id = ?`, [id]);
    res.json({ ...updated, saldada: nuevaActiva === 0 });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// DELETE /deudas/:id?firebase_uid= — archivar deuda (activa=0)
router.delete('/deudas/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [result] = await db.execute(
      `UPDATE deudas SET activa = 0 WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Deuda no encontrada' });
    res.json({ message: 'Deuda archivada' });
    _logInfo(`/deudas/${id}`, `Deuda archivada (id=${id})`, firebase_uid);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// GET /deudas/:id/abonos — Historial de pagos registrados para una deuda
router.get('/deudas/:id/abonos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT id, nombre, monto, fecha, created_at
       FROM registros_gasto
       WHERE origen_deuda_id = ? AND firebase_uid = ?
       ORDER BY fecha DESC, created_at DESC`,
      [id, firebase_uid]
    );
    const total = rows.reduce((s, r) => s + Number(r.monto), 0);
    res.json({ abonos: rows, total_abonado: parseFloat(total.toFixed(2)) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /deudas/proyeccion?firebase_uid=X — situación actual sin extra
router.get('/deudas/proyeccion', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`,
      [firebase_uid]
    );
    if (!deudas.length) return res.json({ sin_deudas: true });

    const totalPendiente  = deudas.reduce((s, d) => s + Number(d.monto_pendiente), 0);
    const totalPagoMinimo = deudas.reduce((s, d) => s + Number(d.pago_minimo || 0), 0);

    const avalanche = _simularDeudas(deudas, 0, 'avalanche');
    const snowball  = _simularDeudas(deudas, 0, 'snowball');

    res.json({
      sin_deudas: false,
      total_pendiente:   parseFloat(totalPendiente.toFixed(2)),
      total_pago_minimo: parseFloat(totalPagoMinimo.toFixed(2)),
      trayectoria_actual: {
        meses: avalanche.meses_totales,
        fecha_fin: avalanche.fecha_fin,
        total_intereses: avalanche.total_intereses,
      },
      avalanche,
      snowball,
      ahorro_avalanche_vs_snowball: parseFloat((snowball.total_intereses - avalanche.total_intereses).toFixed(2)),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /deudas/simulador?firebase_uid=X&extra_mensual=150&estrategia=avalanche
router.get('/deudas/simulador', async (req, res) => {
  const { firebase_uid, extra_mensual = 0, estrategia = 'avalanche' } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`,
      [firebase_uid]
    );
    if (!deudas.length) return res.json({ sin_deudas: true });

    const sinExtra  = _simularDeudas(deudas, 0, estrategia);
    const conExtra  = _simularDeudas(deudas, Number(extra_mensual), estrategia);
    const mesesAhorrados = sinExtra.meses_totales - conExtra.meses_totales;
    const interesesAhorrados = parseFloat((sinExtra.total_intereses - conExtra.total_intereses).toFixed(2));

    // Cuál deuda se ataca primero con el extra
    const deudaObjetivo = conExtra.orden.find(d => d.mes_saldado != null);

    res.json({
      extra_mensual: Number(extra_mensual),
      estrategia,
      sin_extra: sinExtra,
      con_extra:  conExtra,
      meses_ahorrados: mesesAhorrados,
      intereses_ahorrados: interesesAhorrados,
      deuda_objetivo: deudaObjetivo || null,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /deudas/plan?firebase_uid=X&estrategia=avalanche&extra_mensual=0
router.get('/deudas/plan', async (req, res) => {
  const { firebase_uid, estrategia = 'avalanche', extra_mensual = 0 } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`,
      [firebase_uid]
    );
    if (!deudas.length) return res.json({ sin_deudas: true });

    const simulacion = _simularDeudas(deudas, Number(extra_mensual), estrategia);
    const hoy = new Date();

    const pasos = simulacion.orden.map((d, i) => {
      const fechaSaldada = d.mes_saldado
        ? new Date(hoy.getFullYear(), hoy.getMonth() + d.mes_saldado, hoy.getDate()).toISOString().slice(0, 10)
        : null;
      return {
        paso: i + 1,
        id: d.id,
        nombre: d.nombre,
        tipo: d.tipo,
        mes_saldado: d.mes_saldado,
        fecha_saldada: fechaSaldada,
        intereses_pagados: d.intereses_pagados,
        recomendacion: i === 0
          ? `Ataca esta primero. Cuando la saldas, mueve su cuota a la siguiente.`
          : `Cuando saldas la anterior, dirige los pagos liberados aquí.`,
      };
    });

    res.json({
      estrategia,
      extra_mensual: Number(extra_mensual),
      meses_totales: simulacion.meses_totales,
      fecha_libertad: simulacion.fecha_fin,
      total_intereses: simulacion.total_intereses,
      pasos,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
