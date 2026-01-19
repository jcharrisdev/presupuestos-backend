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
      SELECT tipo_periodo, fecha_inicio_configurada
      FROM presupuestos
      WHERE id = ?
        AND firebase_uid = ?
      `,
      [presupuestoId, firebaseUid]
    );

  if (!presupuesto) {
    throw new Error('Presupuesto no encontrado');
  }

  const { tipo_periodo, fecha_inicio_configurada } = presupuesto;

  // 2️⃣ Buscar período activo
  const [periodos] = await connection
    .promise()
    .execute(
      `
      SELECT *
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
    if (hoy <= periodo.fecha_fin) {
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
  fechaInicioConfigurada
) {
  const fechaInicio = new Date(fechaInicioConfigurada);
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
app.post('/presupuestos', (req, res) => {
  const { nombre,
    monto_total,
    firebase_uid,
    tipo_periodo,
    fecha_inicio_configurada} = req.body;

  if (!nombre ||
    monto_total == null ||
    !firebase_uid ||
    !tipo_periodo ||
    !fecha_inicio_configurada) {
    return res.status(400).json({ error: 'nombre y monto_total son obligatorios' });
  }
  
  if (!['quincenal', 'mensual'].includes(tipo_periodo)) {
    return res.status(400).json({
      error: 'tipo_periodo inválido',
    });
  }

  const sql = `
   INSERT INTO presupuestos (
      nombre,
      monto_total,
      firebase_uid,
      tipo_periodo,
      fecha_inicio_configurada
    )
    VALUES (?, ?, ?, ?, ?)
  `;

  connection.execute(sql, [ nombre,
      monto_total,
      firebase_uid,
      tipo_periodo,
      fecha_inicio_configurada], (err, result) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: 'Error al crear presupuesto' });
    }

    res.status(201).json({
        id: result.insertId,
        nombre,
        monto_total,
        tipo_periodo,
        fecha_inicio_configurada
    });
  });
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
app.get('/presupuestos/:id/gastos', (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;

   if(!firebase_uid){
      return res.status(400).json({error: 'firebase_uid es requerido'});
  }
  await getPeriodoActivo(id, firebase_uid);


  const sql = `
    SELECT *
    FROM gastos g
    WHERE g.presupuesto_id = ?
    and g.firebase_uid = ?
    AND (
      g.tipo != 'ahorro'
      OR (
        g.tipo = 'ahorro'
        AND g.numero_quincena = (
          SELECT MIN(g2.numero_quincena)
          FROM gastos g2
          WHERE g2.ahorro_id = g.ahorro_id
            AND g2.pagado = 0
        )
      )
    )
  `;

  connection.execute(sql, [id, firebase_uid], (err, results) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: 'Error al obtener gastos' });
    }
    res.json(results);
  });
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
   SERVER
========================= */
const PORT = process.env.PORT || 3002;

app.listen(PORT, () => {
  console.log(`🚀 Servidor activo en puerto ${PORT}`);
});
