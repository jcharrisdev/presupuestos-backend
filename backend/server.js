const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');

const app = express();

/* =========================
   MIDDLEWARE
========================= */
app.use(cors());
app.use(express.json());

/* =========================
   VARIABLES DE ENTORNO (LOG CONTROLADO)
========================= */
console.log('DB HOST:', process.env.MYSQLHOST);
console.log('DB USER:', process.env.MYSQLUSER);
console.log('DB NAME:', process.env.MYSQLDATABASE);
console.log('DB PORT:', process.env.MYSQLPORT);

/* =========================
   CONEXIÓN MYSQL
========================= */
const connection = mysql.createConnection({
  host: process.env.MYSQLHOST,
  user: process.env.MYSQLUSER,
  password: process.env.MYSQLPASSWORD,
  database: process.env.MYSQLDATABASE,
  port: Number(process.env.MYSQLPORT),
});

connection.connect((err) => {
  if (err) {
    console.error('❌ Error conectando a MySQL:', err);
    process.exit(1);
  }
  console.log('✅ Conectado a MySQL');
});

/* =========================
   Nuevo:periodos 
========================= */
/* =========================
   ===== NUEVO: PERIODOS =====
========================= */

async function getPeriodoActivo(presupuestoId, firebaseUid) {
  const hoy = new Date().toISOString().split('T')[0];

  // 1️⃣ Obtener reglas del presupuesto
  const [[presupuesto]] = await connection
    .promise()
    .execute(
      `
      SELECT tipo_periodo, dia_inicio_periodo
      FROM presupuestos
      WHERE id = ?
        AND firebase_uid = ?
      `,
      [presupuestoId, firebaseUid]
    );

  if (!presupuesto) {
    throw new Error('Presupuesto no encontrado');
  }

  const { tipo_periodo, dia_inicio_periodo } = presupuesto;


  // 2️⃣ Buscar período activo
  const [periodos] = await connection
    .promise()
    .execute(
      `
      SELECT *, DATE(NOW()) fecha_hoy
      FROM periodos
      WHERE presupuesto_id = ?
        AND firebase_uid = ?
        AND estado = 'activo'
      LIMIT 1
      `,
      [presupuestoId, firebaseUid]
    );

  if (periodos.length > 0) {
    const periodo = periodos[0];

    // 3️⃣ Si sigue vigente → devolverlo
    if ( periodo.fecha_hoy <= periodo.fecha_fin) {
      return periodo;
    }

    // 4️⃣ Si venció → cerrarlo
    await connection
      .promise()
      .execute(
        `
        UPDATE periodos
        SET estado = 'cerrado',
            closed_at = NOW()
        WHERE id = ?
        `,
        [periodo.id]
      );

    // el siguiente período comienza al día siguiente
    return await crearNuevoPeriodo(
      presupuestoId,
      firebaseUid,
      tipo_periodo,
      periodo.fecha_fin
    );
  }

  // 5️⃣ No existe ningún período → crear el primero
  return await crearPrimerPeriodo(
    presupuestoId,
    firebaseUid,
    tipo_periodo,
    fecha_inicio_configurada
  );
}

async function crearPrimerPeriodo(
  presupuestoId,
  firebaseUid,
  tipoPeriodo,
  dia_inicio_periodo
) {
  const hoy = new Date();

let fechaInicio = new Date(
  hoy.getFullYear(),
  hoy.getMonth(),
  dia_inicio_periodo
);

// Si el día ya pasó este mes, iniciar en el próximo período
if (fechaInicio < hoy) {
  if (tipoPeriodo === 'quincenal') {
    fechaInicio.setDate(fechaInicio.getDate() + 14);
  } else {
    fechaInicio.setMonth(fechaInicio.getMonth() + 1);
  }
}

  const fechaFin = calcularFechaFin(fechaInicio, tipoPeriodo);

  const [[{ ultimo }]] = await connection
    .promise()
    .execute(
      `
      SELECT MAX(numero_periodo) AS ultimo
      FROM periodos
      WHERE presupuesto_id = ?
      `,
      [presupuestoId]
    );

  const numeroPeriodo = (ultimo || 0) + 1;

  const [result] = await connection
    .promise()
    .execute(
      `
      INSERT INTO periodos (
        presupuesto_id,
        firebase_uid,
        numero_periodo,
        tipo_periodo,
        fecha_inicio,
        fecha_fin,
        estado
      )
      VALUES (?, ?, ?, ?, ?, ?, 'activo')
      `,
      [
        presupuestoId,
        firebaseUid,
        numeroPeriodo,
        tipoPeriodo,
        fechaInicio.toISOString().split('T')[0],
        fechaFin
      ]
    );

  return {
    id: result.insertId,
    presupuesto_id: presupuestoId,
    firebase_uid: firebaseUid,
    numero_periodo: numeroPeriodo,
    tipo_periodo: tipoPeriodo,
    fecha_inicio: fechaInicio,
    fecha_fin: fechaFin,
    estado: 'activo',
  };
}


async function crearNuevoPeriodo(
  presupuestoId,
  firebaseUid,
  tipoPeriodo,
  fechaFinAnterior
) {
  const fechaInicio = new Date(fechaFinAnterior);
  fechaInicio.setDate(fechaInicio.getDate() + 1);

  const fechaFin = calcularFechaFin(fechaInicio, tipoPeriodo);

  const [[{ ultimo }]] = await connection
    .promise()
    .execute(
      `
      SELECT MAX(numero_periodo) AS ultimo
      FROM periodos
      WHERE presupuesto_id = ?
      `,
      [presupuestoId]
    );

  const numeroPeriodo = (ultimo || 0) + 1;

  const [result] = await connection
    .promise()
    .execute(
      `
      INSERT INTO periodos (
        presupuesto_id,
        firebase_uid,
        numero_periodo,
        tipo_periodo,
        fecha_inicio,
        fecha_fin,
        estado
      )
      VALUES (?, ?, ?, ?, ?, ?, 'activo')
      `,
      [
        presupuestoId,
        firebaseUid,
        numeroPeriodo,
        tipoPeriodo,
        fechaInicio.toISOString().split('T')[0],
        fechaFin
      ]
    );

  return {
    id: result.insertId,
    presupuesto_id: presupuestoId,
    firebase_uid: firebaseUid,
    numero_periodo: numeroPeriodo,
    tipo_periodo: tipoPeriodo,
    fecha_inicio: fechaInicio,
    fecha_fin: fechaFin,
    estado: 'activo',
  };
}


function calcularFechaFin(fechaInicio, tipoPeriodo) {
  const fechaFin = new Date(fechaInicio);

  if (tipoPeriodo === 'quincenal') {
    fechaFin.setDate(fechaFin.getDate() + 14);
  } else {
    fechaFin.setMonth(fechaFin.getMonth() + 1);
    fechaFin.setDate(fechaFin.getDate() - 1);
  }

  return fechaFin.toISOString().split('T')[0];
}





/* =========================
   RUTA HEALTHCHECK
========================= */
app.get('/', (req, res) => {
  res.json({ status: 'Backend funcionando correctamente' });
});

/* =========================
   PRESUPUESTOS
========================= */

// Crear presupuesto
app.post('/presupuestos', async (req, res) => {
  const {
    nombre,
    monto_total,
    firebase_uid,
    tipo_periodo,
    dia_inicio_periodo
  } = req.body;

  if (!nombre || monto_total == null || !firebase_uid || !tipo_periodo || !dia_inicio_periodo) {
    return res.status(400).json({ error: 'Datos incompletos' });
  }

  try {
    // 1️⃣ Crear presupuesto
    const [result] = await connection.promise().execute(
      `
      INSERT INTO presupuestos (
        nombre,
        monto_total,
        firebase_uid,
        tipo_periodo,
        dia_inicio_periodo
      )
      VALUES (?, ?, ?, ?, ?)
      `,
      [nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo]
    );

    const presupuestoId = result.insertId;

    // 2️⃣ CREAR PRIMER PERÍODO (ESTO FALTABA)
    await crearPrimerPeriodo(
      presupuestoId,
      firebase_uid,
      tipo_periodo,
      dia_inicio_periodo
    );

    // 3️⃣ Responder OK
    res.status(201).json({
      id: presupuestoId,
      nombre,
      monto_total,
      tipo_periodo,
      dia_inicio_periodo
    });

  } catch (error) {
    console.error('Error creando presupuesto:', error);
    res.status(500).json({ error: 'Error al crear presupuesto' });
  }
});


// Obtener presupuestos
app.get('/presupuestos', (req, res) => {
   const { firebase_uid } = req.query;
   if(!firebase_uid) {
      return res.status(400).json({
       error: 'firebase_uid es requerido',  
      })
   }

   const sql =`select * from presupuestos where firebase_uid = ? order by id desc`;
   
  connection.execute(
    sql, [firebase_uid],
    (err, results) => {
      if (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error al obtener presupuestos' });
      }
      res.json(results);
    }
  );
});

/* =========================
   GASTOS
========================= */

// Agregar gasto
app.post('/gastos', (req, res) => {
  const { presupuesto_id, descripcion, monto, tipo, fecha, firebase_uid} = req.body;

  if (!presupuesto_id || !descripcion || monto == null || !tipo || !fecha || !firebase_uid) {
    return res.status(400).json({ error: 'Datos incompletos' });
  }

  const sql = `
    INSERT INTO gastos (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid)
    VALUES (?, ?, ?, ?, ?, 0, ?)
  `;

  connection.execute(
    sql,
    [presupuesto_id, descripcion, monto, tipo, fecha, firebase_uid],
    (err, result) => {
      if (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error al agregar gasto' });
      }

      res.status(201).json({
        id: result.insertId,
        presupuesto_id,
        descripcion,
        monto,
        tipo,
        fecha,
        pagado: 0,
        firebase_uid
      });
    }
  );
});

// Obtener gastos por presupuesto
app.get('/presupuestos/:id/gastos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;

  if (!firebase_uid) {
    return res.status(400).json({ error: 'firebase_uid es requerido' });
  }

  try {
    await getPeriodoActivo(id, firebase_uid);

    const sql = `
      SELECT *
      FROM gastos
      WHERE presupuesto_id = ?
        AND firebase_uid = ?
      ORDER BY id DESC
    `;

    connection.execute(sql, [id, firebase_uid], (err, results) => {
      if (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error al obtener gastos' });
      }

      res.json(results);
    });
  } catch (error) {
    console.error('Error en período activo:', error);
    res.status(500).json({ error: error.message });
  }
});


// Actualizar estado de gasto
app.put('/gastos/:id', (req, res) => {
  const { id } = req.params;
  const { pagado } = req.body;

  if (pagado === undefined) {
    return res.status(400).json({ error: 'Campo pagado es obligatorio' });
  }

  const pagadoValue = pagado === true || pagado === 1 ? 1 : 0;

  const sql = `
    UPDATE gastos
    SET pagado = ?
    WHERE id = ?
  `;

  connection.execute(sql, [pagadoValue, id], (err, result) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: 'Error al actualizar gasto' });
    }

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Gasto no encontrado' });
    }

    res.json({
      message: 'Estado actualizado',
      id,
      pagado: pagadoValue
    });
  });
});

// Reanudar gastos fijos
app.put('/presupuestos/:id/gastos/reanudar-fijos', (req, res) => {
  const { id } = req.params;

  const sql = `
    UPDATE gastos
    SET pagado = 0
    WHERE presupuesto_id = ?
      AND tipo = 'fijo'
  `;

  connection.execute(sql, [id], (err, result) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: 'Error al reanudar gastos fijos' });
    }

    res.json({
      message: 'Gastos fijos reanudados',
      afectados: result.affectedRows
    });
  });
});

// Eliminar gasto
app.delete('/gastos/:id', (req, res) => {
  const { id } = req.params;

  connection.execute(
    'DELETE FROM gastos WHERE id = ?',
    [id],
    (err, result) => {
      if (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error al eliminar gasto' });
      }

      if (result.affectedRows === 0) {
        return res.status(404).json({ error: 'Gasto no encontrado' });
      }

      res.json({ message: 'Gasto eliminado' });
    }
  );
});

/* =========================
   MOVIMIENTOS
========================= */

app.post('/movimientos/bulk', async (req, res) => {
  const { presupuesto_id, firebase_uid, items } = req.body;

  if (
    !presupuesto_id ||
    !firebase_uid ||
    !Array.isArray(items) ||
    items.length === 0
  ) {
    return res.status(400).json({ error: 'Datos incompletos' });
  }

  const conn = connection.promise();

  try {
    // 1️⃣ Obtener período activo
    const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);

    // 2️⃣ Iniciar transacción
    await conn.beginTransaction();

    for (const item of items) {
      const { gasto_id, descripcion, monto, tipo } = item;

      if (!gasto_id || !descripcion || monto <= 0) continue;

      // 3️⃣ Insertar movimiento
      await conn.execute(
        `
        INSERT INTO movimientos (
          gasto_id,
          presupuesto_id,
          periodo_id,
          firebase_uid,
          descripcion,
          monto,
          tipo,
          pagado,
          fecha_pagado
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, 1, NOW())
        `,
        [
          gasto_id,
          presupuesto_id,
          periodo.id,
          firebase_uid,
          descripcion,
          monto,
          tipo
        ]
      );

      // 4️⃣ Si es fijo por X períodos → reducir contador
      if (tipo === 'fijo_x_periodo') {
        await conn.execute(
          `
          UPDATE gastos
          SET periodos_restantes = periodos_restantes - 1
          WHERE id = ?
            AND periodos_restantes > 0
          `,
          [gasto_id]
        );
      }
    }

    // 5️⃣ Commit
    await conn.commit();

    res.status(201).json({
      message: 'Movimientos creados correctamente',
      periodo_id: periodo.id,
    });

  } catch (error) {
    await conn.rollback();
    console.error('Error creando movimientos:', error);
    res.status(500).json({ error: 'Error al crear movimientos' });
  }
});

// ===============================
// DETALLE DEL PRESUPUESTO (MOVIMIENTOS)
// ===============================
app.get('/presupuestos/:id/detalle', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;

  if (!firebase_uid) {
    return res.status(400).json({ error: 'firebase_uid es requerido' });
  }

  try {
    // 1️⃣ Obtener período activo (o crearlo si no existe)
    const periodo = await getPeriodoActivo(id, firebase_uid);

    // 2️⃣ Obtener movimientos del período activo
    const [movimientos] = await connection.promise().execute(
      `
      SELECT *
      FROM movimientos
      WHERE presupuesto_id = ?
        AND periodo_id = ?
        AND firebase_uid = ?
      ORDER BY id DESC
      `,
      [id, periodo.id, firebase_uid]
    );

    // 3️⃣ Totales
    let totalFijo = 0;
    let totalNoFijo = 0;
    let totalAhorro = 0;

    movimientos.forEach(m => {
      if (m.tipo === 'fijo') totalFijo += Number(m.monto);
      if (m.tipo === 'no fijo') totalNoFijo += Number(m.monto);
      if (m.tipo === 'ahorro') totalAhorro += Number(m.monto);
    });

    const totalGastado = totalFijo + totalNoFijo + totalAhorro;
    const pagados = movimientos.filter(m => m.pagado === 1).length;
    const porcentajePagados =
      movimientos.length > 0 ? pagados / movimientos.length : 0;

    // 4️⃣ Respuesta
    res.json({
      periodo,
      movimientos,
      resumen: {
        totalFijo,
        totalNoFijo,
        totalAhorro,
        totalGastado,
        porcentajePagados,
      },
    });

  } catch (error) {
    console.error('Error detalle presupuesto:', error);
    res.status(500).json({ error: error.message });
  }
});

// ===============================
// CREAR MOVIMIENTOS DESDE GASTOS
// ===============================
app.post('/presupuestos/:id/movimientos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, items } = req.body;

  if (!firebase_uid || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'Datos incompletos' });
  }

  try {
    // 1️⃣ Obtener período activo
    const periodo = await getPeriodoActivo(id, firebase_uid);

    // 2️⃣ Procesar cada gasto seleccionado
    for (const item of items) {
      const { gasto_id, monto } = item;

      if (!gasto_id || monto == null || monto <= 0) continue;

      // Obtener definición del gasto
      const [[gasto]] = await connection.promise().execute(
        `
        SELECT *
        FROM gastos
        WHERE id = ?
          AND presupuesto_id = ?
          AND firebase_uid = ?
        `,
        [gasto_id, id, firebase_uid]
      );

      if (!gasto) continue;

      // Insertar movimiento
      await connection.promise().execute(
        `
        INSERT INTO movimientos (
          presupuesto_id,
          periodo_id,
          gasto_id,
          descripcion,
          monto,
          tipo,
          pagado,
          firebase_uid,
          created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())
        `,
        [
          id,
          periodo.id,
          gasto.id,
          gasto.descripcion,
          monto,
          gasto.tipo,
          firebase_uid
        ]
      );
    }

    res.status(201).json({
      message: 'Movimientos creados correctamente',
      periodo_id: periodo.id
    });

  } catch (error) {
    console.error('Error creando movimientos:', error);
    res.status(500).json({ error: error.message });
  }
});

// ===============================
// GASTOS SELECCIONABLES (MODAL)
// ===============================
app.get('/presupuestos/:id/gastos-seleccionables', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;

  if (!firebase_uid) {
    return res.status(400).json({ error: 'firebase_uid es requerido' });
  }

  try {
    // 1️⃣ Obtener período activo
    const periodo = await getPeriodoActivo(id, firebase_uid);

    // 2️⃣ Obtener gastos elegibles
    const [gastos] = await connection.promise().execute(
      `
      SELECT g.*
      FROM gastos g
      WHERE g.presupuesto_id = ?
        AND g.firebase_uid = ?
        AND (
          g.tipo = 'no fijo'
          OR (
            g.tipo = 'fijo_x_periodo'
            AND (
              g.periodos_restantes IS NULL
              OR g.periodos_restantes > 0
            )
          )
        )
      ORDER BY g.descripcion
      `,
      [id, firebase_uid]
    );

    res.json({
      periodo_id: periodo.id,
      gastos
    });

  } catch (error) {
    console.error('Error obteniendo gastos seleccionables:', error);
    res.status(500).json({ error: error.message });
  }
});

// ===============================
// MARCAR MOVIMIENTO COMO PAGADO
// ===============================
app.put('/movimientos/:id/pagar', async (req, res) => {
  const { id } = req.params;
  const { pagado } = req.body;

  if (pagado === undefined) {
    return res.status(400).json({ error: 'Campo pagado es obligatorio' });
  }

  const pagadoValue = pagado === true || pagado === 1 ? 1 : 0;

  try {
    // 1️⃣ Obtener movimiento
    const [[movimiento]] = await connection
      .promise()
      .execute(
        `
        SELECT *
        FROM movimientos
        WHERE id = ?
        `,
        [id]
      );

    if (!movimiento) {
      return res.status(404).json({ error: 'Movimiento no encontrado' });
    }

    // 2️⃣ Marcar como pagado
    await connection
      .promise()
      .execute(
        `
        UPDATE movimientos
        SET pagado = ?,
            fecha_pagado = CASE
              WHEN ? = 1 THEN NOW()
              ELSE NULL
            END
        WHERE id = ?
        `,
        [pagadoValue, pagadoValue, id]
      );

    res.json({
      message: 'Movimiento actualizado',
      id,
      pagado: pagadoValue,
    });

  } catch (error) {
    console.error('Error pagando movimiento:', error);
    res.status(500).json({ error: error.message });
  }
});


/* =========================
   SERVER
========================= */
const PORT = process.env.PORT || 3002;

app.listen(PORT, () => {
  console.log(`🚀 Servidor activo en puerto ${PORT}`);
});
