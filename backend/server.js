const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

/* =========================
   CONEXIÓN MYSQL (Pool)
========================= */
const pool = mysql.createPool({
  host: process.env.MYSQLHOST,
  user: process.env.MYSQLUSER,
  password: process.env.MYSQLPASSWORD,
  database: process.env.MYSQLDATABASE,
  port: Number(process.env.MYSQLPORT),
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
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
    `SELECT *, DATE(NOW()) fecha_hoy FROM periodos
     WHERE presupuesto_id = ? AND firebase_uid = ? AND estado = 'activo' LIMIT 1`,
    [presupuestoId, firebaseUid]
  );

  if (periodos.length > 0) {
    const periodo = periodos[0];
    if (periodo.fecha_hoy <= periodo.fecha_fin) return periodo;
    await db.execute(
      `UPDATE periodos SET estado = 'cerrado', closed_at = NOW() WHERE id = ?`,
      [periodo.id]
    );
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
      `INSERT INTO movimientos (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
       VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())`,
      [presupuestoId, periodoId, gasto.id, gasto.descripcion, gasto.monto, gasto.tipo, firebaseUid]
    );
    if (gasto.tipo === 'fijo_x_periodo') {
      await db.execute(
        `UPDATE gastos SET numero_quincena = numero_quincena - 1 WHERE id = ? AND numero_quincena > 0`,
        [gasto.id]
      );
    }
  }
}

async function crearPrimerPeriodo(presupuestoId, firebaseUid, tipoPeriodo, dia_inicio_periodo) {
  const hoy = new Date();
  let fechaInicio = new Date(hoy.getFullYear(), hoy.getMonth(), dia_inicio_periodo);
  if (fechaInicio < hoy) {
    if (tipoPeriodo === 'quincenal') fechaInicio.setDate(fechaInicio.getDate() + 14);
    else fechaInicio.setMonth(fechaInicio.getMonth() + 1);
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
  const [[{ ultimo }]] = await db.execute(
    `SELECT MAX(numero_periodo) AS ultimo FROM periodos WHERE presupuesto_id = ?`,
    [presupuestoId]
  );
  const numeroPeriodo = (ultimo || 0) + 1;
  const [result] = await db.execute(
    `INSERT INTO periodos (presupuesto_id, firebase_uid, numero_periodo, tipo_periodo, fecha_inicio, fecha_fin, estado)
     VALUES (?, ?, ?, ?, ?, ?, 'activo')`,
    [presupuestoId, firebaseUid, numeroPeriodo, tipoPeriodo, fechaInicio.toISOString().split('T')[0], fechaFin]
  );
  await generarMovimientosPeriodo(presupuestoId, result.insertId, firebaseUid);
  return {
    id: result.insertId, presupuesto_id: presupuestoId, firebase_uid: firebaseUid,
    numero_periodo: numeroPeriodo, tipo_periodo: tipoPeriodo,
    fecha_inicio: fechaInicio, fecha_fin: fechaFin, estado: 'activo',
  };
}

function calcularFechaFin(fechaInicio, tipoPeriodo) {
  const fechaFin = new Date(fechaInicio);
  if (tipoPeriodo === 'quincenal') fechaFin.setDate(fechaFin.getDate() + 14);
  else { fechaFin.setMonth(fechaFin.getMonth() + 1); fechaFin.setDate(fechaFin.getDate() - 1); }
  return fechaFin.toISOString().split('T')[0];
}

/* =========================
   HEALTHCHECK
========================= */
app.get('/', (req, res) => res.json({ status: 'Backend funcionando correctamente' }));

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
  } catch (error) {
    console.error('Error creando presupuesto:', error);
    res.status(500).json({ error: 'Error al crear presupuesto' });
  }
});

app.get('/presupuestos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [results] = await db.execute(
      `SELECT * FROM presupuestos WHERE firebase_uid = ? ORDER BY id DESC`, [firebase_uid]
    );
    res.json(results);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al obtener presupuestos' });
  }
});

app.put('/presupuestos/:id', async (req, res) => {
  const { id } = req.params;
  const { nombre, monto_total, firebase_uid } = req.body;
  if (!nombre || monto_total == null || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [result] = await db.execute(
      `UPDATE presupuestos SET nombre = ?, monto_total = ? WHERE id = ? AND firebase_uid = ?`,
      [nombre, monto_total, id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Presupuesto no encontrado' });
    res.json({ message: 'Presupuesto actualizado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al actualizar presupuesto' });
  }
});

/* =========================
   GASTOS
========================= */

// Ruta especial ANTES de /:id para evitar conflicto de rutas
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

    // Crear movimiento en período activo
    try {
      const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);
      await db.execute(
        `INSERT INTO movimientos (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
         VALUES (?, ?, ?, ?, ?, 'ahorro', 0, ?, NOW())`,
        [presupuesto_id, periodo.id, gastoId, descripcion, monto, firebase_uid]
      );
    } catch (_) {}

    res.status(201).json({ id: gastoId, message: 'Ahorro/Meta creado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al crear ahorro/meta' });
  }
});

app.post('/gastos', async (req, res) => {
  const { presupuesto_id, descripcion, monto, tipo, fecha, firebase_uid } = req.body;
  if (!presupuesto_id || !descripcion || monto == null || !tipo || !fecha || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });

  const fechaStr = fecha.split('T')[0];

  try {
    const [result] = await db.execute(
      `INSERT INTO gastos (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid) VALUES (?, ?, ?, ?, ?, 0, ?)`,
      [presupuesto_id, descripcion, monto, tipo, fechaStr, firebase_uid]
    );
    const gastoId = result.insertId;

    // Auto-crear movimiento en el período activo para gastos fijos y de ahorro
    if (tipo === 'fijo' || tipo === 'fijo_x_periodo' || tipo === 'ahorro') {
      try {
        const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);
        await db.execute(
          `INSERT INTO movimientos (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
           VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())`,
          [presupuesto_id, periodo.id, gastoId, descripcion, monto, tipo, firebase_uid]
        );
      } catch (_) {
        // Sin período activo aún — el movimiento se creará cuando inicie el período
      }
    }

    res.status(201).json({ id: gastoId, presupuesto_id, descripcion, monto, tipo, fecha: fechaStr, pagado: 0, firebase_uid });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al agregar gasto' });
  }
});

app.get('/presupuestos/:id/gastos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    await getPeriodoActivo(id, firebase_uid);
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

app.put('/gastos/:id', async (req, res) => {
  const { id } = req.params;
  const { pagado } = req.body;
  if (pagado === undefined) return res.status(400).json({ error: 'Campo pagado es obligatorio' });
  const pagadoValue = pagado === true || pagado === 1 ? 1 : 0;
  try {
    const [result] = await db.execute(`UPDATE gastos SET pagado = ? WHERE id = ?`, [pagadoValue, id]);
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ message: 'Estado actualizado', id, pagado: pagadoValue });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al actualizar gasto' });
  }
});

app.put('/presupuestos/:id/gastos/reanudar-fijos', async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await db.execute(
      `UPDATE gastos SET pagado = 0 WHERE presupuesto_id = ? AND tipo = 'fijo'`, [id]
    );
    res.json({ message: 'Gastos fijos reanudados', afectados: result.affectedRows });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al reanudar gastos fijos' });
  }
});

app.delete('/gastos/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await db.execute(`DELETE FROM gastos WHERE id = ?`, [id]);
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ message: 'Gasto eliminado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al eliminar gasto' });
  }
});

/* =========================
   AHORROS (vista de metas)
========================= */
app.get('/ahorros', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [ahorros] = await db.execute(
      `SELECT g.id, g.descripcion AS nombre, g.monto AS monto_meta,
              COALESCE(SUM(m.monto_pagado_real), 0) AS monto_ahorrado
       FROM gastos g
       LEFT JOIN movimientos m ON m.gasto_id = g.id AND m.pagado = 1
       WHERE g.firebase_uid = ? AND g.tipo = 'ahorro'
       GROUP BY g.id`,
      [firebase_uid]
    );
    res.json(ahorros);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al obtener ahorros' });
  }
});

app.delete('/ahorros/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await db.execute(`DELETE FROM gastos WHERE id = ? AND tipo = 'ahorro'`, [id]);
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Ahorro no encontrado' });
    res.json({ message: 'Ahorro eliminado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al eliminar ahorro' });
  }
});

/* =========================
   MOVIMIENTOS
========================= */
app.get('/presupuestos/:id/detalle', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
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
    res.json({
      periodo,
      movimientos,
      resumen: {
        totalFijo, totalNoFijo, totalAhorro,
        totalGastado: totalFijo + totalNoFijo + totalAhorro,
        porcentajePagados: movimientos.length > 0 ? pagados / movimientos.length : 0,
      },
    });
  } catch (error) {
    console.error('Error detalle:', error);
    res.status(500).json({ error: error.message });
  }
});

app.post('/presupuestos/:id/movimientos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, items } = req.body;
  if (!firebase_uid || !Array.isArray(items) || items.length === 0)
    return res.status(400).json({ error: 'Datos incompletos' });

  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    for (const item of items) {
      const { gasto_id, monto } = item;
      if (!gasto_id || monto == null || monto <= 0) continue;
      const [[gasto]] = await db.execute(
        `SELECT * FROM gastos WHERE id = ? AND presupuesto_id = ? AND firebase_uid = ?`,
        [gasto_id, id, firebase_uid]
      );
      if (!gasto) continue;

      // Verificar que no exista ya un movimiento para este gasto en este período
      const [[existing]] = await db.execute(
        `SELECT id FROM movimientos WHERE gasto_id = ? AND periodo_id = ? AND firebase_uid = ?`,
        [gasto_id, periodo.id, firebase_uid]
      );
      if (existing) continue;

      await db.execute(
        `INSERT INTO movimientos (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())`,
        [id, periodo.id, gasto.id, gasto.descripcion, monto, gasto.tipo, firebase_uid]
      );
    }
    res.status(201).json({ message: 'Movimientos creados correctamente', periodo_id: periodo.id });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

app.get('/presupuestos/:id/gastos-seleccionables', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });

  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);

    // Gastos no fijo que aún no tienen movimiento en este período
    const [gastos] = await db.execute(
      `SELECT g.* FROM gastos g
       WHERE g.presupuesto_id = ? AND g.firebase_uid = ? AND g.tipo = 'no fijo'
         AND NOT EXISTS (
           SELECT 1 FROM movimientos m WHERE m.gasto_id = g.id AND m.periodo_id = ?
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

app.put('/movimientos/:id/pagar', async (req, res) => {
  const { id } = req.params;
  const { pagado, monto_pagado_real, firebase_uid } = req.body;
  if (pagado === undefined || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  if (pagado === 1 && (!monto_pagado_real || monto_pagado_real <= 0))
    return res.status(400).json({ error: 'Monto pagado real inválido' });

  try {
    const [[movimiento]] = await db.execute(`SELECT id FROM movimientos WHERE id = ?`, [id]);
    if (!movimiento) return res.status(404).json({ error: 'Movimiento no encontrado' });

    await db.execute(
      `UPDATE movimientos SET pagado = ?, monto_pagado_real = ?, pagado_por_uid = ?,
       fecha_pagado = CASE WHEN ? = 1 THEN NOW() ELSE NULL END WHERE id = ?`,
      [pagado, pagado ? monto_pagado_real : null, pagado ? firebase_uid : null, pagado, id]
    );
    res.json({ message: 'Movimiento actualizado correctamente' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/* =========================
   SERVER
========================= */
const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log(`🚀 Servidor activo en puerto ${PORT}`));
