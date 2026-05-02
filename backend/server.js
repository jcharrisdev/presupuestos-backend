const express = require('express');
const mysql   = require('mysql2');
const cors    = require('cors');
const cron    = require('node-cron');

const app = express();
app.use(cors());
app.use(express.json());

/* =========================
   CONEXIÓN MYSQL (Pool)
========================= */
const pool = mysql.createPool({
  host: process.env.MYSQLHOST, user: process.env.MYSQLUSER,
  password: process.env.MYSQLPASSWORD, database: process.env.MYSQLDATABASE,
  port: Number(process.env.MYSQLPORT),
  waitForConnections: true, connectionLimit: 10, queueLimit: 0,
});
pool.getConnection((err, conn) => {
  if (err) { console.error('❌ Error conectando a MySQL:', err); return; }
  console.log('✅ Conectado a MySQL');
  conn.release();
});
const db = pool.promise();

/* =========================
   LÓGICA DE PERÍODOS
========================= */
async function getPeriodoActivo(presupuestoId, firebaseUid) {
  const [[presupuesto]] = await db.execute(
    `SELECT tipo_periodo, dia_inicio_periodo FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
    [presupuestoId, firebaseUid]
  );
  if (!presupuesto) throw new Error('Presupuesto no encontrado');
  const { tipo_periodo, dia_inicio_periodo } = presupuesto;
  const [periodos] = await db.execute(
    `SELECT *, DATE(NOW()) fecha_hoy FROM periodos WHERE presupuesto_id = ? AND firebase_uid = ? AND estado = 'activo' LIMIT 1`,
    [presupuestoId, firebaseUid]
  );
  if (periodos.length > 0) {
    const periodo = periodos[0];
    const hoyStr = periodo.fecha_hoy instanceof Date ? periodo.fecha_hoy.toISOString().split('T')[0] : String(periodo.fecha_hoy);
    const finStr  = periodo.fecha_fin  instanceof Date ? periodo.fecha_fin.toISOString().split('T')[0]  : String(periodo.fecha_fin);
    if (hoyStr <= finStr) return periodo;
    await db.execute(`UPDATE periodos SET estado = 'cerrado', closed_at = NOW() WHERE id = ?`, [periodo.id]);
    return crearNuevoPeriodo(presupuestoId, firebaseUid, tipo_periodo, periodo.fecha_fin);
  }
  return crearPrimerPeriodo(presupuestoId, firebaseUid, tipo_periodo, dia_inicio_periodo);
}

async function generarMovimientosPeriodo(presupuestoId, periodoId, firebaseUid) {
  const [gastos] = await db.execute(
    `SELECT * FROM gastos WHERE presupuesto_id = ? AND firebase_uid = ?
     AND (tipo = 'fijo' OR tipo = 'ahorro' OR (tipo = 'fijo_x_periodo' AND numero_quincena > 0))`,
    [presupuestoId, firebaseUid]
  );
  for (const gasto of gastos) {
    await db.execute(
      `INSERT INTO movimientos (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())`,
      [presupuestoId, periodoId, gasto.id, gasto.descripcion, gasto.monto, gasto.tipo, firebaseUid]
    );
    if (gasto.tipo === 'fijo_x_periodo') {
      await db.execute(`UPDATE gastos SET numero_quincena = numero_quincena - 1 WHERE id = ? AND numero_quincena > 0`, [gasto.id]);
    }
  }
}

async function crearPrimerPeriodo(presupuestoId, firebaseUid, tipoPeriodo, dia_inicio_periodo) {
  const hoy = new Date();
  const hoyStr = hoy.toISOString().split('T')[0];
  let fechaInicio = new Date(Date.UTC(hoy.getUTCFullYear(), hoy.getUTCMonth(), dia_inicio_periodo));
  if (fechaInicio.toISOString().split('T')[0] < hoyStr) {
    if (tipoPeriodo === 'quincenal') fechaInicio.setUTCDate(fechaInicio.getUTCDate() + 14);
    else fechaInicio.setUTCMonth(fechaInicio.getUTCMonth() + 1);
  }
  return _insertarPeriodo(presupuestoId, firebaseUid, tipoPeriodo, fechaInicio);
}

async function crearNuevoPeriodo(presupuestoId, firebaseUid, tipoPeriodo, fechaFinAnterior) {
  const fechaInicio = new Date(fechaFinAnterior);
  fechaInicio.setDate(fechaInicio.getDate() + 1);
  return _insertarPeriodo(presupuestoId, firebaseUid, tipoPeriodo, fechaInicio);
}

async function _insertarPeriodo(presupuestoId, firebaseUid, tipoPeriodo, fechaInicio) {
  const fechaFin = calcularFechaFin(fechaInicio, tipoPeriodo);
  const [[{ ultimo }]] = await db.execute(`SELECT MAX(numero_periodo) AS ultimo FROM periodos WHERE presupuesto_id = ?`, [presupuestoId]);
  const numeroPeriodo = (ultimo || 0) + 1;
  const [result] = await db.execute(
    `INSERT INTO periodos (presupuesto_id, firebase_uid, numero_periodo, tipo_periodo, fecha_inicio, fecha_fin, estado) VALUES (?, ?, ?, ?, ?, ?, 'activo')`,
    [presupuestoId, firebaseUid, numeroPeriodo, tipoPeriodo, fechaInicio.toISOString().split('T')[0], fechaFin]
  );
  await generarMovimientosPeriodo(presupuestoId, result.insertId, firebaseUid);
  return { id: result.insertId, presupuesto_id: presupuestoId, firebase_uid: firebaseUid, numero_periodo: numeroPeriodo, tipo_periodo: tipoPeriodo, fecha_inicio: fechaInicio, fecha_fin: fechaFin, estado: 'activo' };
}

function calcularFechaFin(fechaInicio, tipoPeriodo) {
  const f = new Date(fechaInicio);
  if (tipoPeriodo === 'quincenal') f.setDate(f.getDate() + 14);
  else { f.setMonth(f.getMonth() + 1); f.setDate(f.getDate() - 1); }
  return f.toISOString().split('T')[0];
}

/* =========================
   LÓGICA DE CALENDARIO
========================= */
function calcularFechasEvento(frecuencia, diaPago, fechaExacta) {
  const fechas = [];
  const hoy = new Date();

  if (frecuencia === 'unico') {
    if (fechaExacta) {
      const f = fechaExacta instanceof Date ? fechaExacta.toISOString().split('T')[0] : String(fechaExacta).split('T')[0];
      fechas.push(f);
    }
    return fechas;
  }

  const MESES = 12;
  for (let m = 0; m < MESES; m++) {
    const anio = hoy.getUTCFullYear() + Math.floor((hoy.getUTCMonth() + m) / 12);
    const mes  = (hoy.getUTCMonth() + m) % 12;
    const ultimoDia = new Date(Date.UTC(anio, mes + 1, 0)).getUTCDate();

    if (frecuencia === 'anual' && m % 12 !== 0) continue;

    const dias = [Math.min(diaPago, ultimoDia)];
    if (frecuencia === 'quincenal') dias.push(Math.min(diaPago + 14, ultimoDia));

    for (const dia of dias) {
      fechas.push(`${anio}-${String(mes + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`);
    }
  }
  return fechas;
}

async function generarEventosCalendario(gastoId, firebaseUid) {
  const [[gasto]] = await db.execute(`SELECT * FROM gastos WHERE id = ? AND firebase_uid = ?`, [gastoId, firebaseUid]);
  if (!gasto || gasto.tipo_fecha !== 'fija') return 0;

  const fechas = calcularFechasEvento(gasto.frecuencia_pago, gasto.dia_pago, gasto.fecha_pago_exacta);
  let insertados = 0;
  for (const fecha of fechas) {
    try {
      await db.execute(
        `INSERT INTO calendario_eventos (firebase_uid, gasto_id, titulo, tipo, fecha_evento, monto_esperado, notificacion_activa, dias_anticipacion) VALUES (?, ?, ?, 'pago', ?, ?, ?, ?)`,
        [firebaseUid, gastoId, gasto.descripcion, fecha, gasto.monto, gasto.genera_notificacion ? 1 : 0, gasto.dias_anticipacion || 3]
      );
      insertados++;
    } catch (err) { console.error('Error insertando evento:', err.message); }
  }
  return insertados;
}

/* =========================
   HEALTHCHECK
========================= */
app.get('/', (req, res) => res.json({ status: 'Backend funcionando correctamente', version: '2.2' }));

/* =========================
   PRESUPUESTOS
========================= */
app.post('/presupuestos', async (req, res) => {
  const { nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo } = req.body;
  if (!nombre || monto_total == null || !firebase_uid || !tipo_periodo || !dia_inicio_periodo)
    return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [result] = await db.execute(
      `INSERT INTO presupuestos (nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo) VALUES (?, ?, ?, ?, ?)`,
      [nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo]
    );
    await crearPrimerPeriodo(result.insertId, firebase_uid, tipo_periodo, dia_inicio_periodo);
    res.status(201).json({ id: result.insertId, nombre, monto_total, tipo_periodo, dia_inicio_periodo });
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al crear presupuesto' }); }
});

app.get('/presupuestos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [results] = await db.execute(`SELECT * FROM presupuestos WHERE firebase_uid = ? ORDER BY id DESC`, [firebase_uid]);
    res.json(results);
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al obtener presupuestos' }); }
});

app.put('/presupuestos/:id', async (req, res) => {
  const { id } = req.params;
  const { nombre, monto_total, firebase_uid } = req.body;
  if (!nombre || monto_total == null || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [result] = await db.execute(`UPDATE presupuestos SET nombre = ?, monto_total = ? WHERE id = ? AND firebase_uid = ?`, [nombre, monto_total, id, firebase_uid]);
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Presupuesto no encontrado' });
    res.json({ message: 'Presupuesto actualizado' });
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al actualizar presupuesto' }); }
});

/* =========================
   GASTOS
========================= */
app.post('/gastos/ahorroMeta', async (req, res) => {
  const { presupuesto_id, descripcion, monto, fecha, firebase_uid } = req.body;
  if (!presupuesto_id || !descripcion || monto == null || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  const fechaStr = fecha ? fecha.split('T')[0] : new Date().toISOString().split('T')[0];
  try {
    const [result] = await db.execute(
      `INSERT INTO gastos (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid) VALUES (?, ?, ?, 'ahorro', ?, 0, ?)`,
      [presupuesto_id, descripcion, monto, fechaStr, firebase_uid]
    );
    const gastoId = result.insertId;
    try {
      const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);
      await db.execute(
        `INSERT INTO movimientos (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at) VALUES (?, ?, ?, ?, ?, 'ahorro', 0, ?, NOW())`,
        [presupuesto_id, periodo.id, gastoId, descripcion, monto, firebase_uid]
      );
    } catch (err) { console.error('⚠️ No se pudo auto-crear movimiento para ahorro:', err.message); }
    res.status(201).json({ id: gastoId, message: 'Ahorro/Meta creado' });
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al crear ahorro/meta' }); }
});

app.post('/gastos', async (req, res) => {
  const {
    presupuesto_id, descripcion, monto, tipo, fecha, firebase_uid,
    tipo_fecha = 'flexible', dia_pago = null, frecuencia_pago = null,
    fecha_pago_exacta = null, genera_notificacion = false, dias_anticipacion = 3
  } = req.body;

  if (!presupuesto_id || !descripcion || monto == null || !tipo || !fecha || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });

  const fechaStr = fecha.split('T')[0];
  const fechaPagoStr = fecha_pago_exacta ? fecha_pago_exacta.split('T')[0] : null;

  try {
    const [result] = await db.execute(
      `INSERT INTO gastos (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid, tipo_fecha, dia_pago, frecuencia_pago, fecha_pago_exacta, genera_notificacion, dias_anticipacion)
       VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)`,
      [presupuesto_id, descripcion, monto, tipo, fechaStr, firebase_uid,
       tipo_fecha, dia_pago, frecuencia_pago, fechaPagoStr, genera_notificacion ? 1 : 0, dias_anticipacion]
    );
    const gastoId = result.insertId;

    // Auto-crear movimiento
    if (tipo === 'fijo' || tipo === 'fijo_x_periodo' || tipo === 'ahorro') {
      try {
        const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);
        await db.execute(
          `INSERT INTO movimientos (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())`,
          [presupuesto_id, periodo.id, gastoId, descripcion, monto, tipo, firebase_uid]
        );
        console.log(`✅ Movimiento auto-creado para gasto ${gastoId} en periodo ${periodo.id}`);
      } catch (err) { console.error('⚠️ No se pudo auto-crear movimiento:', err.message); }
    }

    // Generar eventos de calendario si tiene fecha fija
    if (tipo_fecha === 'fija') {
      const count = await generarEventosCalendario(gastoId, firebase_uid);
      console.log(`📅 ${count} eventos de calendario generados para gasto ${gastoId}`);
    }

    res.status(201).json({ id: gastoId, presupuesto_id, descripcion, monto, tipo, fecha: fechaStr, pagado: 0, firebase_uid });
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al agregar gasto' }); }
});

app.get('/presupuestos/:id/gastos', async (req, res) => {
  const { id } = req.params; const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    await getPeriodoActivo(id, firebase_uid);
    const [results] = await db.execute(`SELECT * FROM gastos WHERE presupuesto_id = ? AND firebase_uid = ? ORDER BY id DESC`, [id, firebase_uid]);
    res.json(results);
  } catch (error) { console.error(error); res.status(500).json({ error: error.message }); }
});

app.put('/gastos/:id', async (req, res) => {
  const { id } = req.params; const { pagado } = req.body;
  if (pagado === undefined) return res.status(400).json({ error: 'Campo pagado es obligatorio' });
  const pagadoValue = pagado === true || pagado === 1 ? 1 : 0;
  try {
    const [result] = await db.execute(`UPDATE gastos SET pagado = ? WHERE id = ?`, [pagadoValue, id]);
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ message: 'Estado actualizado', id, pagado: pagadoValue });
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al actualizar gasto' }); }
});

app.put('/presupuestos/:id/gastos/reanudar-fijos', async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await db.execute(`UPDATE gastos SET pagado = 0 WHERE presupuesto_id = ? AND tipo = 'fijo'`, [id]);
    res.json({ message: 'Gastos fijos reanudados', afectados: result.affectedRows });
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al reanudar gastos fijos' }); }
});

app.delete('/gastos/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await db.execute(`DELETE FROM gastos WHERE id = ?`, [id]);
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ message: 'Gasto eliminado' });
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al eliminar gasto' }); }
});

/* =========================
   AHORROS
========================= */
app.get('/ahorros', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [ahorros] = await db.execute(
      `SELECT g.id, g.descripcion AS nombre, g.monto AS monto_meta, COALESCE(SUM(m.monto_pagado_real), 0) AS monto_ahorrado
       FROM gastos g LEFT JOIN movimientos m ON m.gasto_id = g.id AND m.pagado = 1
       WHERE g.firebase_uid = ? AND g.tipo = 'ahorro' GROUP BY g.id`,
      [firebase_uid]
    );
    res.json(ahorros);
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al obtener ahorros' }); }
});

app.delete('/ahorros/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await db.execute(`DELETE FROM gastos WHERE id = ? AND tipo = 'ahorro'`, [id]);
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Ahorro no encontrado' });
    res.json({ message: 'Ahorro eliminado' });
  } catch (error) { console.error(error); res.status(500).json({ error: 'Error al eliminar ahorro' }); }
});

/* =========================
   MOVIMIENTOS
========================= */
app.get('/presupuestos/:id/detalle', async (req, res) => {
  const { id } = req.params; const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    const [movimientos] = await db.execute(
      `SELECT * FROM movimientos WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ? ORDER BY id DESC`,
      [id, periodo.id, firebase_uid]
    );
    let totalFijo = 0, totalNoFijo = 0, totalAhorro = 0;
    movimientos.forEach(m => {
      if (m.tipo === 'fijo' || m.tipo === 'fijo_x_periodo') totalFijo += Number(m.monto);
      if (m.tipo === 'no fijo') totalNoFijo += Number(m.monto);
      if (m.tipo === 'ahorro') totalAhorro += Number(m.monto);
    });
    const pagados = movimientos.filter(m => m.pagado === 1).length;
    res.json({ periodo, movimientos, resumen: { totalFijo, totalNoFijo, totalAhorro, totalGastado: totalFijo + totalNoFijo + totalAhorro, porcentajePagados: movimientos.length > 0 ? pagados / movimientos.length : 0 } });
  } catch (error) { console.error('Error detalle:', error); res.status(500).json({ error: error.message }); }
});

app.post('/presupuestos/:id/movimientos', async (req, res) => {
  const { id } = req.params; const { firebase_uid, items } = req.body;
  if (!firebase_uid || !Array.isArray(items) || items.length === 0) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    for (const item of items) {
      const { gasto_id, monto } = item;
      if (!gasto_id || monto == null || monto <= 0) continue;
      const [[gasto]] = await db.execute(`SELECT * FROM gastos WHERE id = ? AND presupuesto_id = ? AND firebase_uid = ?`, [gasto_id, id, firebase_uid]);
      if (!gasto) continue;
      const [[existing]] = await db.execute(`SELECT id FROM movimientos WHERE gasto_id = ? AND periodo_id = ? AND firebase_uid = ?`, [gasto_id, periodo.id, firebase_uid]);
      if (existing) continue;
      await db.execute(
        `INSERT INTO movimientos (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())`,
        [id, periodo.id, gasto.id, gasto.descripcion, monto, gasto.tipo, firebase_uid]
      );
    }
    res.status(201).json({ message: 'Movimientos creados correctamente', periodo_id: periodo.id });
  } catch (error) { console.error(error); res.status(500).json({ error: error.message }); }
});

app.get('/presupuestos/:id/gastos-seleccionables', async (req, res) => {
  const { id } = req.params; const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    const [gastos] = await db.execute(
      `SELECT g.* FROM gastos g WHERE g.presupuesto_id = ? AND g.firebase_uid = ? AND g.tipo = 'no fijo'
       AND NOT EXISTS (SELECT 1 FROM movimientos m WHERE m.gasto_id = g.id AND m.periodo_id = ?) ORDER BY g.descripcion`,
      [id, firebase_uid, periodo.id]
    );
    res.json({ periodo_id: periodo.id, gastos });
  } catch (error) { console.error(error); res.status(500).json({ error: error.message }); }
});

app.put('/movimientos/:id/pagar', async (req, res) => {
  const { id } = req.params; const { pagado, monto_pagado_real, firebase_uid } = req.body;
  if (pagado === undefined || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  if (pagado === 1 && (!monto_pagado_real || monto_pagado_real <= 0)) return res.status(400).json({ error: 'Monto pagado real inválido' });
  try {
    const [[movimiento]] = await db.execute(`SELECT id FROM movimientos WHERE id = ?`, [id]);
    if (!movimiento) return res.status(404).json({ error: 'Movimiento no encontrado' });
    await db.execute(
      `UPDATE movimientos SET pagado = ?, monto_pagado_real = ?, pagado_por_uid = ?, fecha_pagado = CASE WHEN ? = 1 THEN NOW() ELSE NULL END WHERE id = ?`,
      [pagado, pagado ? monto_pagado_real : null, pagado ? firebase_uid : null, pagado, id]
    );
    res.json({ message: 'Movimiento actualizado correctamente' });
  } catch (error) { console.error(error); res.status(500).json({ error: error.message }); }
});

/* =========================
   CALENDARIO
========================= */
app.get('/calendario/eventos', async (req, res) => {
  const { firebase_uid, mes, anio } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    let sql = `SELECT ce.*, g.tipo as gasto_tipo FROM calendario_eventos ce LEFT JOIN gastos g ON ce.gasto_id = g.id WHERE ce.firebase_uid = ?`;
    const params = [firebase_uid];
    if (mes && anio) { sql += ` AND YEAR(ce.fecha_evento) = ? AND MONTH(ce.fecha_evento) = ?`; params.push(anio, mes); }
    sql += ` ORDER BY ce.fecha_evento ASC`;
    const [eventos] = await db.execute(sql, params);
    res.json(eventos);
  } catch (error) { console.error(error); res.status(500).json({ error: error.message }); }
});

app.post('/calendario/generar', async (req, res) => {
  const { gasto_id, firebase_uid } = req.body;
  if (!gasto_id || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const count = await generarEventosCalendario(gasto_id, firebase_uid);
    res.json({ message: `${count} eventos generados`, count });
  } catch (error) { console.error(error); res.status(500).json({ error: error.message }); }
});

app.put('/calendario/eventos/:id/estado', async (req, res) => {
  const { id } = req.params; const { estado, firebase_uid } = req.body;
  if (!estado || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  if (!['pendiente','pagado','vencido'].includes(estado)) return res.status(400).json({ error: 'Estado inválido' });
  try {
    const [result] = await db.execute(`UPDATE calendario_eventos SET estado = ? WHERE id = ? AND firebase_uid = ?`, [estado, id, firebase_uid]);
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Evento no encontrado' });
    res.json({ message: 'Estado actualizado', estado });
  } catch (error) { console.error(error); res.status(500).json({ error: error.message }); }
});

app.delete('/calendario/eventos/:id', async (req, res) => {
  const { id } = req.params; const { firebase_uid, solo_este } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    let sql, params;
    if (solo_este === 'false') {
      const [[ev]] = await db.execute(`SELECT gasto_id, fecha_evento FROM calendario_eventos WHERE id = ?`, [id]);
      if (!ev) return res.status(404).json({ error: 'Evento no encontrado' });
      const fechaStr = ev.fecha_evento instanceof Date ? ev.fecha_evento.toISOString().split('T')[0] : String(ev.fecha_evento).split('T')[0];
      sql = `DELETE FROM calendario_eventos WHERE gasto_id = ? AND firebase_uid = ? AND fecha_evento >= ?`;
      params = [ev.gasto_id, firebase_uid, fechaStr];
    } else {
      sql = `DELETE FROM calendario_eventos WHERE id = ? AND firebase_uid = ?`;
      params = [id, firebase_uid];
    }
    const [result] = await db.execute(sql, params);
    res.json({ message: `${result.affectedRows} evento(s) eliminado(s)` });
  } catch (error) { console.error(error); res.status(500).json({ error: error.message }); }
});

/* =========================
   CRON JOB — VENCIDOS
========================= */
cron.schedule('0 0 * * *', async () => {
  try {
    const [result] = await db.execute(`UPDATE calendario_eventos SET estado = 'vencido' WHERE estado = 'pendiente' AND fecha_evento < CURDATE()`);
    console.log(`⏰ Cron vencidos: ${result.affectedRows} eventos actualizados`);
  } catch (err) { console.error('Error en cron vencimientos:', err); }
}, { timezone: 'America/Panama' });

/* =========================
   SERVER
========================= */
const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log(`🚀 Servidor activo en puerto ${PORT}`));
